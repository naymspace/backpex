defmodule Backpex.Integration.Index.MetricsTest do
  use Backpex.ConnCase, async: true

  test "renders a value metric with its select and format", %{conn: conn} do
    for likes <- [100, 200, 300], do: insert(:post, likes: likes)

    conn
    |> visit(~p"/admin/posts")
    |> assert_has("div", text: "Total likes")
    |> assert_has("div", text: "600 likes")
  end
end
