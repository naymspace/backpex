defmodule Backpex.PreferencesControllerTest do
  use ExUnit.Case, async: true

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

  describe "update/2 with single preference" do
    test "updates a single preference", %{conn: conn} do
      params = %{"key" => "global.theme", "value" => "dark"}

      conn = PreferencesController.update(conn, params)

      assert conn.status == 200
      assert Jason.decode!(conn.resp_body) == %{"ok" => true}

      session_prefs = Plug.Conn.get_session(conn, Preferences.session_key())
      assert session_prefs == %{"global" => %{"theme" => "dark"}}
    end

    test "updates nested preference", %{conn: conn} do
      params = %{"key" => "resource.UserLive.columns", "value" => %{"name" => true, "email" => false}}

      conn = PreferencesController.update(conn, params)

      assert conn.status == 200

      session_prefs = Plug.Conn.get_session(conn, Preferences.session_key())

      assert session_prefs == %{
               "resource" => %{
                 "UserLive" => %{
                   "columns" => %{"name" => true, "email" => false}
                 }
               }
             }
    end

    test "preserves existing preferences", %{conn: conn} do
      conn = Plug.Conn.put_session(conn, Preferences.session_key(), %{"global" => %{"theme" => "light"}})
      params = %{"key" => "global.sidebar_open", "value" => false}

      conn = PreferencesController.update(conn, params)

      session_prefs = Plug.Conn.get_session(conn, Preferences.session_key())

      assert session_prefs == %{
               "global" => %{
                 "theme" => "light",
                 "sidebar_open" => false
               }
             }
    end

    test "handles boolean values", %{conn: conn} do
      params = %{"key" => "global.sidebar_open", "value" => true}

      conn = PreferencesController.update(conn, params)

      session_prefs = Plug.Conn.get_session(conn, Preferences.session_key())
      assert session_prefs == %{"global" => %{"sidebar_open" => true}}
    end
  end

  describe "update/2 with batch preferences" do
    test "updates multiple preferences at once", %{conn: conn} do
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

      assert session_prefs == %{
               "global" => %{
                 "theme" => "dark",
                 "sidebar_open" => false
               }
             }
    end

    test "handles empty preferences list", %{conn: conn} do
      params = %{"preferences" => []}

      conn = PreferencesController.update(conn, params)

      assert conn.status == 200

      session_prefs = Plug.Conn.get_session(conn, Preferences.session_key())
      assert session_prefs == nil or session_prefs == %{}
    end

    test "ignores invalid entries in batch", %{conn: conn} do
      params = %{
        "preferences" => [
          %{"key" => "global.theme", "value" => "dark"},
          %{"invalid" => "entry"},
          %{"key" => "global.sidebar_open", "value" => true}
        ]
      }

      conn = PreferencesController.update(conn, params)

      assert conn.status == 200

      session_prefs = Plug.Conn.get_session(conn, Preferences.session_key())

      assert session_prefs == %{
               "global" => %{
                 "theme" => "dark",
                 "sidebar_open" => true
               }
             }
    end
  end
end
