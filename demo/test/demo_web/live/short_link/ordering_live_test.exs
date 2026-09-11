defmodule DemoWeb.Live.ShortLink.OrderingLiveTest do
  use DemoWeb.ConnCase, async: false

  import Demo.EctoFactory
  import Phoenix.LiveViewTest

  # Short links have primary_key: :short_key and no :id column at all. The
  # default init_order derives from the primary key, so it is short_key ascending.

  describe "default ordering" do
    test "orders by short_key ascending by default", %{conn: conn} do
      insert(:short_link, short_key: "ccc", url: "https://example.com/c")
      insert(:short_link, short_key: "aaa", url: "https://example.com/a")
      insert(:short_link, short_key: "bbb", url: "https://example.com/b")

      conn
      |> visit(~p"/admin/short-links")
      |> assert_has("table tbody tr", count: 3)
      |> assert_has("table tbody tr:first-child td", text: "aaa")
      |> assert_has("table tbody tr:nth-child(2) td", text: "bbb")
      |> assert_has("table tbody tr:last-child td", text: "ccc")
    end
  end

  describe "ordering via URL params" do
    test "orders by short_key ascending", %{conn: conn} do
      insert(:short_link, short_key: "cherry", url: "https://example.com/c")
      insert(:short_link, short_key: "apple", url: "https://example.com/a")
      insert(:short_link, short_key: "banana", url: "https://example.com/b")

      params = %{"order_by" => "short_key", "order_direction" => "asc"}

      conn
      |> visit(~p"/admin/short-links?#{params}")
      |> assert_has("table tbody tr", count: 3)
      |> assert_has("table tbody tr:first-child td", text: "apple")
      |> assert_has("table tbody tr:last-child td", text: "cherry")
    end

    test "orders by short_key descending", %{conn: conn} do
      insert(:short_link, short_key: "cherry", url: "https://example.com/c")
      insert(:short_link, short_key: "apple", url: "https://example.com/a")
      insert(:short_link, short_key: "banana", url: "https://example.com/b")

      params = %{"order_by" => "short_key", "order_direction" => "desc"}

      conn
      |> visit(~p"/admin/short-links?#{params}")
      |> assert_has("table tbody tr", count: 3)
      |> assert_has("table tbody tr:first-child td", text: "cherry")
      |> assert_has("table tbody tr:last-child td", text: "apple")
    end
  end

  describe "invalid ordering params" do
    test "falls back to default order_by for invalid order_by field", %{conn: conn} do
      insert(:short_link, short_key: "ccc", url: "https://example.com/c")
      insert(:short_link, short_key: "aaa", url: "https://example.com/a")
      insert(:short_link, short_key: "bbb", url: "https://example.com/b")

      params = %{"order_by" => "nonexistent_field", "order_direction" => "asc"}

      conn
      |> visit(~p"/admin/short-links?#{params}")
      |> assert_has("table tbody tr", count: 3)
      # falls back to the default order column (:short_key)
      |> assert_has("table tbody tr:first-child td", text: "aaa")
      |> assert_has("table tbody tr:nth-child(2) td", text: "bbb")
      |> assert_has("table tbody tr:last-child td", text: "ccc")
    end

    test "falls back to default direction for invalid order_direction", %{conn: conn} do
      insert(:short_link, short_key: "cherry", url: "https://example.com/c")
      insert(:short_link, short_key: "apple", url: "https://example.com/a")
      insert(:short_link, short_key: "banana", url: "https://example.com/b")

      params = %{"order_by" => "short_key", "order_direction" => "INVALID"}

      conn
      |> visit(~p"/admin/short-links?#{params}")
      |> assert_has("table tbody tr", count: 3)
      # order_by=short_key is valid, direction falls back to default: asc
      |> assert_has("table tbody tr:first-child td", text: "apple")
      |> assert_has("table tbody tr:last-child td", text: "cherry")
    end
  end

  describe "ordering via column header click" do
    test "clicking URL Suffix column toggles the default short_key order to descending", %{conn: conn} do
      insert(:short_link, short_key: "cherry", url: "https://example.com/c")
      insert(:short_link, short_key: "apple", url: "https://example.com/a")
      insert(:short_link, short_key: "banana", url: "https://example.com/b")

      conn
      |> visit(~p"/admin/short-links")
      # short_key is already the default order column, so clicking it flips the direction
      |> assert_has("table tbody tr:first-child td", text: "apple")
      |> unwrap(fn view ->
        view
        |> element("a", "URL Suffix")
        |> render_click()
      end)
      |> assert_has("table tbody tr:first-child td", text: "cherry")
      |> assert_has("table tbody tr:nth-child(2) td", text: "banana")
      |> assert_has("table tbody tr:last-child td", text: "apple")
    end
  end
end
