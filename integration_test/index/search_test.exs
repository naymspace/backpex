defmodule Backpex.Integration.Index.SearchTest do
  use Backpex.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "finds items by a searchable field", %{conn: conn} do
    insert(:tag, name: "Elixir")
    insert(:tag, name: "Phoenix")

    conn
    |> visit(~p"/admin/tags")
    |> assert_has("table tbody tr", count: 2)
    |> search("Elixir")
    |> assert_has("table tbody tr", count: 1)
    |> refute_has("tr", text: "Phoenix")
    |> assert_has("tr", text: "Elixir")
  end

  test "finds items by a field with a select expression and by fields that are only shown in forms", %{conn: conn} do
    insert(:user, first_name: "John", last_name: "Doe")
    insert(:user, first_name: "Jane", last_name: "Smith")

    conn
    |> visit(~p"/admin/users")
    |> assert_has("table tbody tr", count: 2)
    |> search("John")
    |> assert_has("table tbody tr", count: 1)
    |> assert_has("tr", text: "John Doe")
  end

  test "finds items with the full-text search", %{conn: conn} do
    insert(:film_review, title: "The Matrix", overview: "A sci-fi classic about reality")
    insert(:film_review, title: "Inception", overview: "Dreams within dreams")

    conn
    |> visit(~p"/admin/film-reviews")
    |> assert_has("table tbody tr", count: 2)
    |> search("Matrix")
    |> assert_has("table tbody tr", count: 1)
    |> assert_has("tr", text: "The Matrix")
    |> refute_has("tr", text: "Inception")
  end

  defp search(session, value) do
    unwrap(session, fn view ->
      view
      |> form("#index-search-form", index_search: %{value: value})
      |> render_change()
    end)
  end
end
