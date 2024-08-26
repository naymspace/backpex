defmodule DemoWeb.TagLiveTest do
  use DemoWeb.ConnCase

  import Demo.Factory
  import Phoenix.LiveViewTest
  import DemoWeb.LiveResourceTests

  describe "tags live resource index" do
    test "is rendered", %{conn: conn} do
      insert_list(3, :tag)

      conn
      |> visit("/admin/tags")
      |> assert_has("h1", text: "Tags", exact: true)
      |> assert_has("button", text: "New Tag", exact: true)
      |> assert_has("button[disabled]", text: "Delete", exact: true)
      |> assert_has("div", text: "Items 1 to 3 (3 total)", exact: true)
    end

    test "search for items", %{conn: conn} do
      insert(:tag, %{name: "Elixir"})
      insert(:tag, %{name: "Phoenix"})

      conn
      |> visit("/admin/tags")
      |> unwrap(fn view ->
          view
          |> form("form[phx-change='index-search']", %{"index_search[value]" => "Elixir"})
          |> render_change()
      end)
      |> refute_has("tr", text: "Phoenix")
      |> assert_has("tr", text: "Elixir")
    end

    test "basic functionality", %{conn: conn} do
      tags = insert_list(3, :tag)

      test_table_rows_count(conn, "/admin/tags", Enum.count(tags))
      test_delete_button_disabled_enabled(conn, "/admin/tags", tags)
      test_show_action_redirect(conn, "/admin/tags", tags)
      test_edit_action_redirect(conn, "/admin/tags", tags)
    end
  end
end
