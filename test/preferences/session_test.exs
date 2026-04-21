defmodule Backpex.Preferences.SessionTest do
  use ExUnit.Case, async: true

  import Plug.Test

  alias Backpex.Preferences
  alias Backpex.Preferences.Session

  describe "preserve/1" do
    test "returns the current value stored under the preferences session key" do
      value = %{"global" => %{"theme" => "dark"}}

      conn =
        conn(:post, "/")
        |> Plug.Test.init_test_session(%{})
        |> Plug.Conn.put_session(Preferences.session_key(), value)

      assert Session.preserve(conn) == value
    end

    test "returns nil when nothing is stored under the preferences session key" do
      conn = conn(:post, "/") |> Plug.Test.init_test_session(%{})

      assert Session.preserve(conn) == nil
    end

    test "ignores unrelated session keys" do
      conn =
        conn(:post, "/")
        |> Plug.Test.init_test_session(%{})
        |> Plug.Conn.put_session("user_id", 42)

      assert Session.preserve(conn) == nil
    end
  end

  describe "restore/2" do
    test "re-puts the preserved value under the preferences session key" do
      value = %{"global" => %{"theme" => "dark"}}
      conn = conn(:post, "/") |> Plug.Test.init_test_session(%{})

      restored = Session.restore(conn, value)

      assert Plug.Conn.get_session(restored, Preferences.session_key()) == value
    end

    test "is a no-op when value is nil" do
      conn = conn(:post, "/") |> Plug.Test.init_test_session(%{})

      restored = Session.restore(conn, nil)

      assert Plug.Conn.get_session(restored, Preferences.session_key()) == nil
    end

    test "does not touch unrelated session keys" do
      conn =
        conn(:post, "/")
        |> Plug.Test.init_test_session(%{})
        |> Plug.Conn.put_session("user_id", 42)

      restored = Session.restore(conn, %{"global" => %{"theme" => "dark"}})

      assert Plug.Conn.get_session(restored, "user_id") == 42
    end
  end

  describe "preserve/restore round-trip across clear_session/1" do
    test "survives the typical UserAuth.renew_session pattern" do
      value = %{"global" => %{"theme" => "dark", "sidebar_open" => false}}

      conn =
        conn(:post, "/")
        |> Plug.Test.init_test_session(%{})
        |> Plug.Conn.put_session(Preferences.session_key(), value)
        |> Plug.Conn.put_session("user_id", 42)

      preserved = Session.preserve(conn)

      renewed =
        conn
        |> Plug.Conn.configure_session(renew: true)
        |> Plug.Conn.clear_session()
        |> Session.restore(preserved)

      # Preferences survived.
      assert Plug.Conn.get_session(renewed, Preferences.session_key()) == value
      # Other session entries were cleared, as clear_session/1 promises.
      assert Plug.Conn.get_session(renewed, "user_id") == nil
    end

    test "no-op path: nothing stored before clear_session still works" do
      conn = conn(:post, "/") |> Plug.Test.init_test_session(%{})

      preserved = Session.preserve(conn)

      renewed =
        conn
        |> Plug.Conn.configure_session(renew: true)
        |> Plug.Conn.clear_session()
        |> Session.restore(preserved)

      assert Plug.Conn.get_session(renewed, Preferences.session_key()) == nil
    end
  end
end
