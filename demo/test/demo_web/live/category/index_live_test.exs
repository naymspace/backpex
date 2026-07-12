defmodule DemoWeb.Live.Category.IndexLiveTest do
  use DemoWeb.ConnCase, async: false

  import Demo.EctoFactory
  import Demo.Support.LiveResourceTests
  import Phoenix.LiveViewTest

  describe "categories live resource index" do
    test "is rendered", %{conn: conn} do
      insert_list(3, :category)

      conn
      |> visit(~p"/admin/categories")
      |> assert_has("h1", text: "Categories", exact: true)
      |> assert_has("button", text: "New Category", exact: true)
      |> assert_has("button[disabled]", text: "Delete", exact: true)
      |> assert_has("div", text: "Items 1 to 3 (3 total)", exact: true)
      |> assert_has("table tbody tr", count: 3)
    end

    test "search for items", %{conn: conn} do
      insert(:category, %{name: "Tech"})
      insert(:category, %{name: "News"})

      conn
      |> visit(~p"/admin/categories")
      |> assert_has(".table tbody tr", count: 2)
      |> unwrap(fn view ->
        view
        |> form("#index-search-form", index_search: %{value: "News"})
        |> render_change()
      end)
      |> assert_has("table tbody tr", count: 1)
      |> refute_has("tr", text: "Tech")
      |> assert_has("tr", text: "News")
    end

    test "basic functionality", %{conn: conn} do
      categories = insert_list(3, :category)

      test_table_rows_count(conn, ~p"/admin/categories", Enum.count(categories))
      test_delete_button_disabled_enabled(conn, ~p"/admin/categories", categories)
      test_show_action_redirect(conn, ~p"/admin/categories", categories)
      test_edit_action_redirect(conn, ~p"/admin/categories", categories)
    end
  end
end
