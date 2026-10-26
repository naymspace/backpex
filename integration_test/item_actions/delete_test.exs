defmodule Backpex.Integration.ItemActions.DeleteTest do
  use Backpex.ConnCase, async: true

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

  defp confirm(session) do
    within(session, "#resource-form", &click_button(&1, "Delete"))
  end
end
