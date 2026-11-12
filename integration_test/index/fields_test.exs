defmodule Backpex.Integration.Index.FieldsTest do
  use Backpex.ConnCase, async: true

  test "formats a currency field", %{conn: conn} do
    insert(:invoice, amount: 150_000)

    conn
    |> visit(~p"/admin/invoices")
    |> assert_has("td", text: "1,500")
  end

  test "renders the anchor_text of a URL field instead of the URL", %{conn: conn} do
    insert(:product, manufacturer: "https://example.com")

    conn
    |> visit(~p"/admin/products")
    |> assert_has("a[href='https://example.com']", text: "Visit example", exact: true)
    |> refute_has("a", text: "https://example.com", exact: true)
  end

  test "renders the before_page_title resource slot", %{conn: conn} do
    insert(:film_review)

    conn
    |> visit(~p"/admin/film-reviews")
    |> assert_has("div", text: "This resource uses the full-text search functionality")
  end
end
