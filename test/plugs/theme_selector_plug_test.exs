defmodule Plugs.ThemeSelectorPlugTest do
  use ExUnit.Case, async: true
  use Plug.Test

  alias Backpex.ThemeSelectorPlug

  describe "ThemeSelectorPlug" do
    test "assigns theme from session" do
      conn =
        conn(:get, "/")
        |> init_test_session(%{"backpex" => %{"theme" => "dark"}})
        |> fetch_session()

      conn = ThemeSelectorPlug.call(conn, [])

      assert conn.assigns.theme == "dark"
    end

    test "assigns nil when no theme in session" do
      conn =
        conn(:get, "/")
        |> init_test_session(%{})
        |> fetch_session()

      conn = ThemeSelectorPlug.call(conn, [])

      assert conn.assigns.theme == nil
    end

    test "assigns nil when backpex key exists but theme key doesn't" do
      conn =
        conn(:get, "/")
        |> init_test_session(%{"backpex" => %{}})
        |> fetch_session()

      conn = ThemeSelectorPlug.call(conn, [])

      assert conn.assigns.theme == nil
    end

    test "init function returns the default value" do
      default = "some default value"
      assert ThemeSelectorPlug.init(default) == default
    end
  end
end
