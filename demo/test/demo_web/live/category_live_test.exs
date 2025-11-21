defmodule DemoWeb.Live.CategoryLiveTest do
  use DemoWeb.ConnCase, async: false

  import Demo.EctoFactory
  import Phoenix.LiveViewTest
  import Demo.Support.LiveResourceTests

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

  describe "categories live resource show" do
    test "is rendered", %{conn: conn} do
      category = insert(:category)

      conn
      |> visit(~p"/admin/categories/#{category.id}/show")
      |> assert_has("h1", text: "Category", exact: true)
      |> assert_has("dt", text: "Name", exact: true)
      |> assert_has("dd", text: category.name, exact: true)
    end
  end

  describe "categories live resource edit" do
    test "is rendered", %{conn: conn} do
      category = insert(:category)

      conn
      |> visit(~p"/admin/categories/#{category.id}/edit")
      |> assert_has("h1", text: "Edit Category", exact: true)
      |> assert_has("button", text: "Cancel", exact: true)
      |> assert_has("button", text: "Save", exact: true)
    end

    test "submit form", %{conn: conn} do
      category = insert(:category, %{name: "Tech"})

      conn
      |> visit(~p"/admin/categories/#{category.id}/edit")
      |> unwrap(fn view ->
        view
        |> form("#resource-form", change: %{name: "New"})
        |> put_submitter("button[value=save]")
        |> render_submit()
      end)
      |> assert_has("table tbody tr", count: 1)
      |> assert_has("p", text: "New", exact: true)
    end
  end

  describe "categories live resource new" do
    test "is rendered", %{conn: conn} do
      conn
      |> visit(~p"/admin/categories/new")
      |> assert_has("h1", text: "New Category", exact: true)
      |> assert_has("button", text: "Cancel", exact: true)
      |> assert_has("button", text: "Save", exact: true)
    end

    test "submit form", %{conn: conn} do
      conn
      |> visit(~p"/admin/categories/new")
      |> unwrap(fn view ->
        view
        |> form("#resource-form", change: %{name: "New"})
        |> put_submitter("button[value=save]")
        |> render_submit()
      end)
      |> assert_has("table tbody tr", count: 1)
      |> assert_has("p", text: "New", exact: true)
    end
  end
end
