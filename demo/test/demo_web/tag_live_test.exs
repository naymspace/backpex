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
      |> assert_has(".table tbody tr", count: 2)
      |> unwrap(fn view ->
        view
        |> form("#index-search-form", index_search: %{value: "Elixir"})
        |> render_change()
      end)
      |> assert_has(".table tbody tr", count: 1)
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

  describe "tags live resource show" do
    test "is rendered", %{conn: conn} do
      tag = insert(:tag)

      conn
      |> visit("/admin/tags/#{tag.id}/show")
      |> assert_has("h1", text: "Tag", exact: true)
      |> assert_has("p", text: "Name", exact: true)
      |> assert_has("p", text: "Inserted At", exact: true)
      |> assert_has("p", text: tag.name, exact: true)
    end
  end

  describe "tags live resource edit" do
    test "is rendered", %{conn: conn} do
      tag = insert(:tag)

      conn
      |> visit("/admin/tags/#{tag.id}/edit")
      |> assert_has("h1", text: "Edit Tag", exact: true)
      |> assert_has("button", text: "Cancel", exact: true)
      |> assert_has("button", text: "Save", exact: true)
    end

    test "submit form", %{conn: conn} do
      tag = insert(:tag, %{name: "Elixir"})

      conn
      |> visit("/admin/tags/#{tag.id}/edit")
      |> unwrap(fn view ->
        view
        |> form("#resource-form", change: %{name: "Phoenix"})
        |> put_submitter("button[value=save]")
        |> render_submit()
      end)
      |> assert_has(".table tbody tr", count: 1)
      |> assert_has("p", text: "Phoenix", exact: true)
    end
  end

  describe "tags live resource new" do
    test "is rendered", %{conn: conn} do
      conn
      |> visit("/admin/tags/new")
      |> assert_has("h1", text: "New Tag", exact: true)
      |> assert_has("button", text: "Cancel", exact: true)
      |> assert_has("button", text: "Save", exact: true)
    end

    test "submit form", %{conn: conn} do
      conn
      |> visit("/admin/tags/new")
      |> unwrap(fn view ->
        view
        |> form("#resource-form", change: %{name: "Phoenix"})
        |> put_submitter("button[value=save]")
        |> render_submit()
      end)
      |> assert_has(".table tbody tr", count: 1)
      |> assert_has("p", text: "Phoenix", exact: true)
    end
  end
end
