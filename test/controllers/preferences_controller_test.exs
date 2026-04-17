defmodule Backpex.PreferencesControllerTest do
  use ExUnit.Case, async: false

  import Plug.Test

  alias Backpex.Preferences
  alias Backpex.PreferencesController

  setup do
    conn =
      conn(:post, "/backpex_preferences")
      |> Plug.Test.init_test_session(%{})
      |> Plug.Conn.put_private(:phoenix_endpoint, __MODULE__)
      |> Plug.Conn.put_req_header("content-type", "application/json")

    {:ok, conn: conn}
  end

  describe "update/2 with a single preference" do
    test "persists the value", %{conn: conn} do
      conn = PreferencesController.update(conn, %{"key" => "global.theme", "value" => "dark"})

      assert conn.status == 200
      assert Jason.decode!(conn.resp_body) == %{"ok" => true}

      session_prefs = Plug.Conn.get_session(conn, Preferences.session_key())
      assert session_prefs == %{"global" => %{"theme" => "dark"}}
    end

    test "persists nested values keyed by module (colon form)", %{conn: conn} do
      conn =
        PreferencesController.update(conn, %{
          "key" => "resource:MyApp.UserLive:columns",
          "value" => %{"name" => true, "email" => false}
        })

      session_prefs = Plug.Conn.get_session(conn, Preferences.session_key())

      assert session_prefs == %{
               "resource" => %{
                 "MyApp.UserLive" => %{
                   "columns" => %{"name" => true, "email" => false}
                 }
               }
             }
    end

    test "preserves existing preferences under other keys", %{conn: conn} do
      conn =
        conn
        |> Plug.Conn.put_session(Preferences.session_key(), %{"global" => %{"theme" => "light"}})
        |> PreferencesController.update(%{"key" => "global.sidebar_open", "value" => false})

      session_prefs = Plug.Conn.get_session(conn, Preferences.session_key())
      assert session_prefs == %{"global" => %{"theme" => "light", "sidebar_open" => false}}
    end
  end

  describe "update/2 with a batch" do
    test "persists all entries atomically", %{conn: conn} do
      params = %{
        "preferences" => [
          %{"key" => "global.theme", "value" => "dark"},
          %{"key" => "global.sidebar_open", "value" => false}
        ]
      }

      conn = PreferencesController.update(conn, params)

      assert conn.status == 200
      assert Jason.decode!(conn.resp_body) == %{"ok" => true}

      session_prefs = Plug.Conn.get_session(conn, Preferences.session_key())
      assert session_prefs == %{"global" => %{"theme" => "dark", "sidebar_open" => false}}
    end

    test "ignores invalid entries in the batch but still persists valid ones", %{conn: conn} do
      params = %{
        "preferences" => [
          %{"key" => "global.theme", "value" => "dark"},
          %{"not_a_preference" => true},
          %{"key" => "global.sidebar_open", "value" => true}
        ]
      }

      conn = PreferencesController.update(conn, params)

      assert conn.status == 200
      session_prefs = Plug.Conn.get_session(conn, Preferences.session_key())
      assert session_prefs == %{"global" => %{"theme" => "dark", "sidebar_open" => true}}
    end

    test "accepts an empty batch as a no-op", %{conn: conn} do
      conn = PreferencesController.update(conn, %{"preferences" => []})

      assert conn.status == 200
      # Nothing was written; session may be nil or an empty map depending on the test adapter.
      assert Plug.Conn.get_session(conn, Preferences.session_key()) in [nil, %{}]
    end
  end

  describe "update/2 invalid requests" do
    test "returns 400 when neither key/value nor preferences list is provided", %{conn: conn} do
      conn = PreferencesController.update(conn, %{"unrelated" => "payload"})

      assert conn.status == 400
      assert Jason.decode!(conn.resp_body) == %{"ok" => false, "error" => "missing key/value"}
    end
  end

  describe "update/2 with an adapter that refuses the write (all-or-nothing)" do
    setup do
      # Route :test prefix to a stub adapter that always errors.
      prior = Application.get_env(:backpex, Backpex.Preferences)

      Application.put_env(:backpex, Backpex.Preferences,
        adapters: [
          {"test.*", Backpex.PreferencesControllerTest.RejectingAdapter, []},
          {:default, Backpex.Preferences.Adapters.Session, []}
        ]
      )

      on_exit(fn ->
        case prior do
          nil -> Application.delete_env(:backpex, Backpex.Preferences)
          value -> Application.put_env(:backpex, Backpex.Preferences, value)
        end
      end)

      :ok
    end

    test "returns {ok: false, errors: [...]} and leaves the session untouched", %{conn: conn} do
      params = %{
        "preferences" => [
          %{"key" => "global.theme", "value" => "dark"},
          %{"key" => "test.thing", "value" => "nope"}
        ]
      }

      conn = PreferencesController.update(conn, params)

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["ok"] == false
      assert [%{"key" => "test.thing", "reason" => _reason}] = body["errors"]

      # Because the batch failed, nothing was written — session is untouched.
      assert Plug.Conn.get_session(conn, Preferences.session_key()) == nil
    end
  end

  defmodule RejectingAdapter do
    @moduledoc false
    @behaviour Backpex.Preferences.Adapter

    @impl Backpex.Preferences.Adapter
    def get(_ctx, _key, _opts), do: {:ok, :not_found}

    @impl Backpex.Preferences.Adapter
    def get_map(_ctx, _prefix, _opts), do: {:ok, %{}}

    @impl Backpex.Preferences.Adapter
    def put(_ctx, _key, _value, _opts), do: {:error, :rejected}
  end
end
