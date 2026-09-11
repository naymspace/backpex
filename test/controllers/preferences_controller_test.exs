defmodule Backpex.PreferencesControllerTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import Plug.Test

  alias Backpex.Preferences
  alias Backpex.Preferences.Adapter
  alias Backpex.Preferences.Adapters.Session
  alias Backpex.Preferences.Keys
  alias Backpex.PreferencesController
  alias Backpex.Test.InMemoryPreferencesAdapter, as: InMemory

  defmodule RecordingAdapter do
    @moduledoc false
    @behaviour Adapter

    @impl Adapter
    def get(_ctx, _key, _opts), do: {:ok, :not_found}

    @impl Adapter
    def get_map(_ctx, _prefix, _opts), do: {:ok, %{}}

    @impl Adapter
    def put(ctx, key, value, _opts) do
      send(self(), {:preference_put, ctx.scope, key, value})
      {:ok, :persisted}
    end
  end

  defmodule ScopeResolver do
    @moduledoc false
    def resolve(%Backpex.Preferences.Context{assigns: %{current_scope: scope}}), do: scope
    def resolve(_ctx), do: :unscoped
  end

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
      conn = PreferencesController.update(conn, %{"key" => Keys.theme(), "value" => "dark"})

      assert conn.status == 200
      assert Jason.decode!(conn.resp_body) == %{"ok" => true}

      session_prefs = Plug.Conn.get_session(conn, Preferences.session_key())
      assert session_prefs == %{"global" => %{"theme" => "dark"}}
    end

    test "persists nested values keyed by module (colon form)", %{conn: conn} do
      conn =
        PreferencesController.update(conn, %{
          "key" => Keys.columns(MyApp.UserLive),
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
        |> PreferencesController.update(%{"key" => Keys.sidebar_open(), "value" => false})

      session_prefs = Plug.Conn.get_session(conn, Preferences.session_key())
      assert session_prefs == %{"global" => %{"theme" => "light", "sidebar_open" => false}}
    end
  end

  describe "update/2 with an application scope" do
    setup do
      prior = Application.get_env(:backpex, Backpex.Preferences)

      Application.put_env(:backpex, Backpex.Preferences,
        adapters: [{:default, RecordingAdapter, []}],
        scope: {ScopeResolver, :resolve, []}
      )

      on_exit(fn ->
        case prior do
          nil -> Application.delete_env(:backpex, Backpex.Preferences)
          value -> Application.put_env(:backpex, Backpex.Preferences, value)
        end
      end)

      :ok
    end

    test "passes tenant-aware conn assigns through the scope resolver", %{conn: conn} do
      scope = %{user_id: 7, tenant_id: 70}
      conn = Plug.Conn.assign(conn, :current_scope, scope)

      conn = PreferencesController.update(conn, %{"key" => Keys.theme(), "value" => "dark"})

      assert conn.status == 200
      assert_received {:preference_put, ^scope, "global.theme", "dark"}
    end
  end

  describe "update/2 with a batch" do
    test "persists every entry", %{conn: conn} do
      params = %{
        "preferences" => [
          %{"key" => Keys.theme(), "value" => "dark"},
          %{"key" => Keys.sidebar_open(), "value" => false}
        ]
      }

      conn = PreferencesController.update(conn, params)

      assert conn.status == 200
      assert Jason.decode!(conn.resp_body) == %{"ok" => true}

      session_prefs = Plug.Conn.get_session(conn, Preferences.session_key())
      assert session_prefs == %{"global" => %{"theme" => "dark", "sidebar_open" => false}}
    end

    test "keeps sibling keys and applies the last value for a repeated key", %{conn: conn} do
      params = %{
        "preferences" => [
          %{"key" => Keys.theme(), "value" => "dark"},
          %{"key" => Keys.sidebar_open(), "value" => false},
          %{"key" => Keys.theme(), "value" => "cupcake"}
        ]
      }

      conn = PreferencesController.update(conn, params)

      assert conn.status == 200

      assert Plug.Conn.get_session(conn, Preferences.session_key()) == %{
               "global" => %{"theme" => "cupcake", "sidebar_open" => false}
             }
    end

    test "ignores invalid entries in the batch but still persists valid ones", %{conn: conn} do
      params = %{
        "preferences" => [
          %{"key" => Keys.theme(), "value" => "dark"},
          %{"not_a_preference" => true},
          %{"key" => Keys.sidebar_open(), "value" => true}
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

  describe "update/2 when an adapter refuses the write (best-effort, first-error-wins)" do
    setup do
      InMemory.reset()
      prior = Application.get_env(:backpex, Backpex.Preferences)

      # Route:
      #   ok.* → in-memory adapter (eager: writes to ETS on put/4)
      #   fail.* → rejecting adapter (always errors)
      #   :default → session
      Application.put_env(:backpex, Backpex.Preferences,
        adapters: [
          {"ok.*", InMemory, []},
          {"fail.*", Backpex.Test.RejectingPreferencesAdapter, []},
          {:default, Session, []}
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

    test "halts at the first error and does not dispatch later entries (short-circuit)", %{conn: conn} do
      # Three-entry batch:
      #   1. ok.before   → InMemory (succeeds, writes ETS row eagerly)
      #   2. fail.middle → Rejecting (fails)
      #   3. ok.after    → InMemory (MUST NOT be dispatched — would write ETS row)
      params = %{
        "preferences" => [
          %{"key" => "ok.before", "value" => "committed"},
          %{"key" => "fail.middle", "value" => "nope"},
          %{"key" => "ok.after", "value" => "should_not_run"}
        ]
      }

      conn = PreferencesController.update(conn, params)

      assert conn.status == 422
      body = Jason.decode!(conn.resp_body)
      assert body["ok"] == false
      assert body["error"] == %{"key" => "fail.middle", "reason" => "rejected"}

      stored = InMemory.dump()

      # Path A: the earlier eager write committed — we do NOT claim rollback.
      assert Map.has_key?(stored, "ok.before")
      assert stored["ok.before"] == "committed"

      # Short-circuit: the entry after the failure was never dispatched, so
      # its ETS row was never written.
      refute Map.has_key?(stored, "ok.after")

      # Session-backed effects collected before the failure are never applied
      # (the controller only calls apply_effects_on_conn on the :ok branch),
      # so the cookie is untouched.
      assert Plug.Conn.get_session(conn, Preferences.session_key()) == nil
    end
  end

  describe "update/2 when the adapter returns :unscoped (anonymous visitor)" do
    setup do
      prior = Application.get_env(:backpex, Backpex.Preferences)

      # Route:
      #   resource.* → unscoped adapter (mimics a DB adapter rejecting
      #                anonymous visitors)
      #   :default   → session
      Application.put_env(:backpex, Backpex.Preferences,
        adapters: [
          {"resource.*", Backpex.Test.UnscopedPreferencesAdapter, []},
          {:default, Session, []}
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

    test "single-write :unscoped returns 200 ok: false reason: unscoped", %{conn: conn} do
      conn =
        PreferencesController.update(conn, %{
          "key" => Keys.columns(MyApp.UserLive),
          "value" => %{"name" => true}
        })

      assert conn.status == 200

      assert Jason.decode!(conn.resp_body) == %{
               "ok" => false,
               "error" => %{"key" => Keys.columns(MyApp.UserLive), "reason" => "unscoped"}
             }
    end

    test "single-write :unscoped does not log a warning", %{conn: conn} do
      log =
        capture_log(fn ->
          PreferencesController.update(conn, %{
            "key" => Keys.columns(MyApp.UserLive),
            "value" => %{"name" => true}
          })
        end)

      refute log =~ "preference batch refused"
      refute log =~ "unscoped"
    end

    test "batch with :unscoped entry still returns 422", %{conn: conn} do
      params = %{
        "preferences" => [
          %{"key" => Keys.theme(), "value" => "dark"},
          %{"key" => Keys.columns(MyApp.UserLive), "value" => %{"name" => true}}
        ]
      }

      conn = PreferencesController.update(conn, params)

      assert conn.status == 422
      body = Jason.decode!(conn.resp_body)
      assert body["ok"] == false
      assert body["error"]["reason"] == "unscoped"
    end
  end

  describe "update/2 with a wrong-typed built-in value" do
    test "returns 422 instead of persisting a value that breaks later renders", %{conn: conn} do
      conn =
        capture_log_result(fn ->
          PreferencesController.update(conn, %{"key" => Keys.sidebar_open(), "value" => "false"})
        end)

      assert conn.status == 422
      body = Jason.decode!(conn.resp_body)
      assert body["error"] == %{"key" => Keys.sidebar_open(), "reason" => "invalid_value"}
      assert Plug.Conn.get_session(conn, Preferences.session_key()) == nil
    end

    test "still accepts keys Backpex does not own", %{conn: conn} do
      conn = PreferencesController.update(conn, %{"key" => "custom.acme.thing", "value" => "anything"})

      assert conn.status == 200

      assert Plug.Conn.get_session(conn, Preferences.session_key()) == %{
               "custom" => %{"acme" => %{"thing" => "anything"}}
             }
    end
  end

  describe "update/2 when the adapter refuses an oversized write" do
    test "returns 422 rather than raising CookieOverflowError", %{conn: conn} do
      conn =
        capture_log_result(fn ->
          PreferencesController.update(conn, %{"key" => Keys.theme(), "value" => String.duplicate("x", 5_000)})
        end)

      assert conn.status == 422
      body = Jason.decode!(conn.resp_body)
      assert body["ok"] == false
      assert body["error"] == %{"key" => Keys.theme(), "reason" => "too_large"}
    end

    test "leaves the session untouched so earlier preferences survive", %{conn: conn} do
      conn = Plug.Conn.put_session(conn, Preferences.session_key(), %{"global" => %{"theme" => "light"}})

      conn =
        capture_log_result(fn ->
          PreferencesController.update(conn, %{"key" => Keys.theme(), "value" => String.duplicate("x", 5_000)})
        end)

      assert Plug.Conn.get_session(conn, Preferences.session_key()) == %{"global" => %{"theme" => "light"}}
    end
  end

  defp capture_log_result(fun) do
    {result, _log} = ExUnit.CaptureLog.with_log(fun)
    result
  end
end
