defmodule Backpex.Integration.HarnessTest do
  use Backpex.ConnCase, async: true

  test "renders the index view of every routed LiveResource", %{conn: conn} do
    insert(:tag, name: "Elixir")

    conn
    |> visit(~p"/admin/tags")
    |> assert_has("h1", text: "Tags")
    |> assert_has("table tbody tr", text: "Elixir")
  end

  test "keeps the data of async tests apart", %{conn: conn} do
    insert(:tag, name: "Phoenix")

    conn
    |> visit(~p"/admin/tags")
    |> assert_has("table tbody tr", count: 1)
  end
end
