defmodule Backpex.Integration.ItemActions.DeleteTest do
  use Backpex.ConnCase, async: true

  alias Backpex.Test.Category
  alias Backpex.Test.Repo

  setup do
    %{category: insert(:category, name: "Elixir")}
  end

  test "deletes the item from the index view", %{conn: conn} do
    conn
    |> visit(~p"/admin/categories")
    |> assert_has("td", text: "Elixir", exact: true)
    # The toolbar has a "Delete" button for the selected items, too.
    |> within("table", &click_button(&1, "Delete"))
    |> confirm()
    |> assert_path(~p"/admin/categories")
    |> refute_has("td", text: "Elixir", exact: true)
    |> assert_has("div", text: "Category has been deleted successfully.", exact: true)
  end

  test "deletes the item from the show view", %{conn: conn, category: category} do
    conn
    |> visit(~p"/admin/categories/#{category.id}/show")
    |> assert_has("dd", text: "Elixir", exact: true)
    |> click_button("Delete")
    |> confirm()
    |> assert_path(~p"/admin/categories")
    |> refute_has("td", text: "Elixir", exact: true)
    |> assert_has("div", text: "Category has been deleted successfully.", exact: true)
  end

  test "does not delete an item when on_item_deleting/2 refuses it", %{conn: conn, category: category} do
    insert(:post, category: category)

    conn
    |> visit(~p"/admin/categories")
    |> within("table", &click_button(&1, "Delete"))
    |> confirm()
    |> assert_has("div", text: "Elixir can't be deleted, because posts belong to it.", exact: true)
    |> assert_has("td", text: "Elixir", exact: true)

    assert Repo.get(Category, category.id)
  end

  test "stays on the show view when on_item_deleting/2 refuses the item", %{conn: conn, category: category} do
    insert(:post, category: category)

    conn
    |> visit(~p"/admin/categories/#{category.id}/show")
    |> click_button("Delete")
    |> confirm()
    |> assert_path(~p"/admin/categories/#{category.id}/show")
    |> assert_has("div", text: "Elixir can't be deleted, because posts belong to it.", exact: true)
    |> assert_has("dd", text: "Elixir", exact: true)

    assert Repo.get(Category, category.id)
  end

  describe "an update of the shown item while the confirmation dialog is open" do
    test "leaves the index view as the place the action returns to", %{conn: conn, category: category} do
      conn
      |> visit(~p"/admin/categories/#{category.id}/show")
      |> click_button("Delete")
      |> receive_update(category)
      |> confirm()
      |> assert_path(~p"/admin/categories")
      |> assert_has("div", text: "Category has been deleted successfully.", exact: true)

      refute Repo.get(Category, category.id)
    end

    test "leaves the return_to param as the place the action returns to", %{conn: conn, category: category} do
      conn
      |> visit(~p"/admin/categories/#{category.id}/show?return_to=/admin/tags")
      |> click_button("Delete")
      |> receive_update(category)
      |> confirm()
      |> assert_path(~p"/admin/tags")

      refute Repo.get(Category, category.id)
    end

    test "lets the edit link return to the show view after cancelling", %{conn: conn, category: category} do
      show_path = ~p"/admin/categories/#{category.id}/show"
      edit_path = ~p"/admin/categories/#{category.id}/edit?#{[return_to: show_path]}"

      conn
      |> visit(show_path)
      |> click_button("Delete")
      |> receive_update(category)
      |> unwrap(&Phoenix.LiveViewTest.render_click(&1, "cancel-action-confirm"))
      |> refute_has("#resource-form")
      |> assert_has("a[href='#{edit_path}']")
    end
  end

  # Sends the event `Backpex.Resource.update/5` broadcasts to the views of the resource.
  defp receive_update(session, item) do
    unwrap(session, fn view ->
      send(view.pid, {"backpex:updated", item})
      Phoenix.LiveViewTest.render(view)
    end)
  end

  defp confirm(session) do
    within(session, "#resource-form", &click_button(&1, "Delete"))
  end
end
