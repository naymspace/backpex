defmodule Backpex.Integration.ItemActions.DeleteTest do
  use Backpex.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup do
    %{category: insert(:category, name: "Elixir")}
  end

  test "deletes the item from the index view", %{conn: conn, category: category} do
    conn
    |> visit(~p"/admin/categories")
    |> assert_has("td", text: "Elixir", exact: true)
    |> unwrap(fn view ->
      view
      |> element("button[aria-label='Delete'][phx-value-item-id='#{category.id}']")
      |> render_click()
    end)
    |> confirm()
    |> assert_path(~p"/admin/categories")
    |> refute_has("td", text: "Elixir", exact: true)
    |> assert_has("div", text: "Category has been deleted successfully.", exact: true)
  end

  test "deletes the item from the show view", %{conn: conn, category: category} do
    conn
    |> visit(~p"/admin/categories/#{category.id}/show")
    |> assert_has("dd", text: "Elixir", exact: true)
    |> unwrap(fn view -> view |> element("#item-action-delete") |> render_click() end)
    |> confirm()
    |> assert_path(~p"/admin/categories")
    |> refute_has("td", text: "Elixir", exact: true)
    |> assert_has("div", text: "Category has been deleted successfully.", exact: true)
  end

  defp confirm(session) do
    unwrap(session, fn view -> view |> form("#resource-form") |> render_submit() end)
  end
end
