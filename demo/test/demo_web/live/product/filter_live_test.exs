defmodule DemoWeb.Live.Product.FilterLiveTest do
  use DemoWeb.ConnCase, async: false

  import Demo.EctoFactory
  import Phoenix.LiveViewTest

  describe "range filter" do
    test "filters by quantity range with start and end", %{conn: conn} do
      insert(:product, name: "Low Stock", quantity: 10)
      insert(:product, name: "Medium Stock", quantity: 50)
      insert(:product, name: "High Stock", quantity: 100)

      conn
      |> visit(~p"/admin/products")
      |> assert_has("table tbody tr", count: 3)
      |> unwrap(fn view ->
        view
        |> form("form[phx-change='change-filter']", filters: %{quantity: %{start: "20", end: "80"}})
        |> render_change()
      end)
      |> assert_has("table tbody tr", count: 1)
      |> refute_has("tr", text: "Low Stock")
      |> assert_has("tr", text: "Medium Stock")
      |> refute_has("tr", text: "High Stock")
    end

    test "filters with only start value via form change", %{conn: conn} do
      insert(:product, name: "Low Stock", quantity: 10)
      insert(:product, name: "Medium Stock", quantity: 50)
      insert(:product, name: "High Stock", quantity: 100)

      conn
      |> visit(~p"/admin/products")
      |> assert_has("table tbody tr", count: 3)
      |> unwrap(fn view ->
        view
        |> form("form[phx-change='change-filter']", filters: %{quantity: %{start: "50"}})
        |> render_change()
      end)
      |> assert_has("table tbody tr", count: 2)
      |> refute_has("tr", text: "Low Stock")
      |> assert_has("tr", text: "Medium Stock")
      |> assert_has("tr", text: "High Stock")
    end

    test "filters with only end value via form change", %{conn: conn} do
      insert(:product, name: "Low Stock", quantity: 10)
      insert(:product, name: "Medium Stock", quantity: 50)
      insert(:product, name: "High Stock", quantity: 100)

      conn
      |> visit(~p"/admin/products")
      |> assert_has("table tbody tr", count: 3)
      |> unwrap(fn view ->
        view
        |> form("form[phx-change='change-filter']", filters: %{quantity: %{end: "50"}})
        |> render_change()
      end)
      |> assert_has("table tbody tr", count: 2)
      |> assert_has("tr", text: "Low Stock")
      |> assert_has("tr", text: "Medium Stock")
      |> refute_has("tr", text: "High Stock")
    end

    test "filters by quantity range via URL params", %{conn: conn} do
      insert(:product, name: "Low Stock", quantity: 10)
      insert(:product, name: "High Stock", quantity: 100)

      params = %{"filters" => %{"quantity" => %{"start" => "50", "end" => "200"}}}

      conn
      |> visit(~p"/admin/products?#{params}")
      |> assert_has("table tbody tr", count: 1)
      |> assert_has("td", text: "High Stock")
      |> refute_has("td", text: "Low Stock")
    end
  end

  describe "clear filter" do
    test "clearing filter via badge resets results", %{conn: conn} do
      insert(:product, name: "Low Stock", quantity: 10)
      insert(:product, name: "High Stock", quantity: 100)

      conn
      |> visit(~p"/admin/products")
      |> assert_has("table tbody tr", count: 2)
      |> unwrap(fn view ->
        view
        |> form("form[phx-change='change-filter']", filters: %{quantity: %{start: "50"}})
        |> render_change()
      end)
      |> assert_has("table tbody tr", count: 1)
      |> unwrap(fn view ->
        view
        |> element("button[phx-click='clear-filter'][phx-value-field='quantity'][aria-label]")
        |> render_click()
      end)
      |> assert_has("table tbody tr", count: 2)
    end
  end

  describe "filter badges" do
    test "shows badge for active quantity filter", %{conn: conn} do
      insert(:product, name: "Widget", quantity: 100)

      params = %{"filters" => %{"quantity" => %{"start" => "50", "end" => "200"}}}

      conn
      |> visit(~p"/admin/products?#{params}")
      |> assert_has("button[aria-label='Clear QTY filter']")
    end

    test "no badge when filter is not active", %{conn: conn} do
      insert(:product, name: "Widget", quantity: 100)

      conn
      |> visit(~p"/admin/products")
      |> refute_has("button[aria-label='Clear QTY filter']")
    end
  end

  describe "filter validation" do
    test "invalid start value does not apply filter", %{conn: conn} do
      insert(:product, name: "Low Stock", quantity: 10)
      insert(:product, name: "High Stock", quantity: 100)

      params = %{"filters" => %{"quantity" => %{"start" => "abc", "end" => ""}}}

      conn
      |> visit(~p"/admin/products?#{params}")
      |> assert_has("table tbody tr", count: 2)
      |> assert_has("td", text: "Low Stock")
      |> assert_has("td", text: "High Stock")
    end

    test "invalid end value does not apply filter", %{conn: conn} do
      insert(:product, name: "Low Stock", quantity: 10)
      insert(:product, name: "High Stock", quantity: 100)

      params = %{"filters" => %{"quantity" => %{"start" => "", "end" => "xyz"}}}

      conn
      |> visit(~p"/admin/products?#{params}")
      |> assert_has("table tbody tr", count: 2)
      |> assert_has("td", text: "Low Stock")
      |> assert_has("td", text: "High Stock")
    end
  end
end
