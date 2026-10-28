defmodule Backpex.Integration.Form.SaveTest do
  use Backpex.ConnCase, async: true

  test "creates an item and returns to the index view", %{conn: conn} do
    conn
    |> visit(~p"/admin/tags/new")
    |> fill_in("Name", with: "Phoenix")
    |> click_button("Save")
    |> assert_path(~p"/admin/tags")
    |> assert_has("table tbody tr", count: 1)
    |> assert_has("p", text: "Phoenix", exact: true)
  end

  test "prefills the form with the item, updates it and returns to the index view", %{conn: conn} do
    tag = insert(:tag, name: "Elixir")

    conn
    |> visit(~p"/admin/tags/#{tag.id}/edit")
    |> assert_has("input", label: "Name", value: "Elixir")
    |> fill_in("Name", with: "Phoenix")
    |> click_button("Save")
    |> assert_path(~p"/admin/tags")
    |> assert_has("table tbody tr", count: 1)
    |> assert_has("p", text: "Phoenix", exact: true)
  end
end
