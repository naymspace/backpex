defmodule Backpex.Integration.Index.MetricsTest do
  use Backpex.ConnCase, async: true

  test "renders the value metrics with their select and format", %{conn: conn} do
    insert(:post, likes: 250, published: true)
    insert(:post, likes: 350, published: true)
    insert(:post, likes: 1000, published: false)

    # Both published and not published posts, so the metrics differ from the number of rows.
    conn
    |> visit(~p"/admin/posts?#{%{"filters" => %{"published" => ["published", "not_published"]}}}")
    |> assert_has("table tbody tr", count: 3)
    |> assert_has(".card-body", text: "Total likes 1600 likes", exact: true)
    |> assert_has(".card-body", text: "Published Posts 2", exact: true)
  end
end
