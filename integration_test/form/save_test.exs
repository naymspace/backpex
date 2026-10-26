defmodule Backpex.Integration.Form.SaveTest do
  use Backpex.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "creates an item and returns to the index view", %{conn: conn} do
    conn
    |> visit(~p"/admin/tags/new")
    |> unwrap(fn view ->
      view
      |> form("#resource-form", change: %{name: "Phoenix"})
      |> put_submitter("button[value=save]")
      |> render_submit()
    end)
    |> assert_path(~p"/admin/tags")
    |> assert_has("table tbody tr", count: 1)
    |> assert_has("p", text: "Phoenix", exact: true)
  end

  test "prefills the form with the item, updates it and returns to the index view", %{conn: conn} do
    tag = insert(:tag, name: "Elixir")

    conn
    |> visit(~p"/admin/tags/#{tag.id}/edit")
    |> assert_has("input[name='change[name]'][value='Elixir']")
    |> unwrap(fn view ->
      view
      |> form("#resource-form", change: %{name: "Phoenix"})
      |> put_submitter("button[value=save]")
      |> render_submit()
    end)
    |> assert_path(~p"/admin/tags")
    |> assert_has("table tbody tr", count: 1)
    |> assert_has("p", text: "Phoenix", exact: true)
  end
end
