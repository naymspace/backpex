defmodule DemoWeb.Live.Product.OrderingLiveTest do
  use DemoWeb.ConnCase, async: false

  import Demo.EctoFactory
  import Phoenix.LiveViewTest

  # Products use default init_order: %{by: :id, direction: :asc}
  # The :manufacturer field has orderable: false
  # Products have binary_id (random UUID) primary keys, so ascending id order is
  # unrelated to insertion order and has to be derived from the inserted records.

  describe "default ordering" do
    test "orders by id ascending by default", %{conn: conn} do
      products = [
        insert(:product, name: "First Product"),
        insert(:product, name: "Second Product"),
        insert(:product, name: "Third Product")
      ]

      [first, second, third] = Enum.sort_by(products, & &1.id)

      conn
      |> visit(~p"/admin/products")
      |> assert_has("table tbody tr", count: 3)
      |> assert_has("table tbody tr:first-child td", text: first.name)
      |> assert_has("table tbody tr:nth-child(2) td", text: second.name)
      |> assert_has("table tbody tr:last-child td", text: third.name)
    end
  end

  describe "ordering via URL params" do
    test "orders by name ascending", %{conn: conn} do
      insert(:product, name: "Cherry")
      insert(:product, name: "Apple")
      insert(:product, name: "Banana")

      params = %{"order_by" => "name", "order_direction" => "asc"}

      conn
      |> visit(~p"/admin/products?#{params}")
      |> assert_has("table tbody tr", count: 3)
      |> assert_has("table tbody tr:first-child td", text: "Apple")
      |> assert_has("table tbody tr:last-child td", text: "Cherry")
    end

    test "orders by name descending", %{conn: conn} do
      insert(:product, name: "Cherry")
      insert(:product, name: "Apple")
      insert(:product, name: "Banana")

      params = %{"order_by" => "name", "order_direction" => "desc"}

      conn
      |> visit(~p"/admin/products?#{params}")
      |> assert_has("table tbody tr", count: 3)
      |> assert_has("table tbody tr:first-child td", text: "Cherry")
      |> assert_has("table tbody tr:last-child td", text: "Apple")
    end

    test "orders by quantity descending", %{conn: conn} do
      insert(:product, name: "Few", quantity: 10)
      insert(:product, name: "Many", quantity: 1000)
      insert(:product, name: "Some", quantity: 100)

      params = %{"order_by" => "quantity", "order_direction" => "desc"}

      conn
      |> visit(~p"/admin/products?#{params}")
      |> assert_has("table tbody tr", count: 3)
      |> assert_has("table tbody tr:first-child td", text: "Many")
      |> assert_has("table tbody tr:last-child td", text: "Few")
    end

    test "orders by price ascending", %{conn: conn} do
      insert(:product, name: "Expensive", price: Money.new(50_000, :USD))
      insert(:product, name: "Cheap", price: Money.new(10_00, :USD))
      insert(:product, name: "Mid", price: Money.new(10_000, :USD))

      params = %{"order_by" => "price", "order_direction" => "asc"}

      conn
      |> visit(~p"/admin/products?#{params}")
      |> assert_has("table tbody tr", count: 3)
      |> assert_has("table tbody tr:first-child td", text: "Cheap")
      |> assert_has("table tbody tr:last-child td", text: "Expensive")
    end
  end

  describe "invalid ordering params" do
    test "falls back to default order_by for invalid order_by field", %{conn: conn} do
      products = [
        insert(:product, name: "First Product"),
        insert(:product, name: "Second Product"),
        insert(:product, name: "Third Product")
      ]

      [first, second, third] = Enum.sort_by(products, & &1.id)

      # order_by falls back to init_order.by (:id), direction stays as provided (:asc)
      params = %{"order_by" => "nonexistent_field", "order_direction" => "asc"}

      conn
      |> visit(~p"/admin/products?#{params}")
      |> assert_has("table tbody tr", count: 3)
      |> assert_has("table tbody tr:first-child td", text: first.name)
      |> assert_has("table tbody tr:nth-child(2) td", text: second.name)
      |> assert_has("table tbody tr:last-child td", text: third.name)
    end

    test "falls back to default direction for invalid order_direction", %{conn: conn} do
      insert(:product, name: "Cherry")
      insert(:product, name: "Apple")
      insert(:product, name: "Banana")

      params = %{"order_by" => "name", "order_direction" => "INVALID"}

      conn
      |> visit(~p"/admin/products?#{params}")
      |> assert_has("table tbody tr", count: 3)
      # order_by=name is valid, direction falls back to default: asc
      |> assert_has("table tbody tr:first-child td", text: "Apple")
      |> assert_has("table tbody tr:last-child td", text: "Cherry")
    end

    test "non-orderable field falls back to default order", %{conn: conn} do
      products = [
        insert(:product, name: "First Product"),
        insert(:product, name: "Second Product"),
        insert(:product, name: "Third Product")
      ]

      [first, second, third] = Enum.sort_by(products, & &1.id)

      params = %{"order_by" => "manufacturer", "order_direction" => "asc"}

      conn
      |> visit(~p"/admin/products?#{params}")
      |> assert_has("table tbody tr", count: 3)
      # manufacturer is orderable: false, falls back to default: id asc
      |> assert_has("table tbody tr:first-child td", text: first.name)
      |> assert_has("table tbody tr:nth-child(2) td", text: second.name)
      |> assert_has("table tbody tr:last-child td", text: third.name)
    end
  end

  describe "ordering via column header click" do
    test "clicking name column orders by name ascending", %{conn: conn} do
      insert(:product, name: "Cherry")
      insert(:product, name: "Apple")
      insert(:product, name: "Banana")

      conn
      |> visit(~p"/admin/products")
      |> unwrap(fn view ->
        view
        |> element("a", "Name")
        |> render_click()
      end)
      |> assert_has("table tbody tr:first-child td", text: "Apple")
      |> assert_has("table tbody tr:last-child td", text: "Cherry")
    end

    test "clicking same column twice toggles order direction", %{conn: conn} do
      insert(:product, name: "Cherry")
      insert(:product, name: "Apple")
      insert(:product, name: "Banana")

      conn
      |> visit(~p"/admin/products")
      # Click name to order asc
      |> unwrap(fn view ->
        view
        |> element("a", "Name")
        |> render_click()
      end)
      |> assert_has("table tbody tr:first-child td", text: "Apple")
      # Click name again to order desc
      |> unwrap(fn view ->
        view
        |> element("a", "Name")
        |> render_click()
      end)
      |> assert_has("table tbody tr:first-child td", text: "Cherry")
      |> assert_has("table tbody tr:last-child td", text: "Apple")
    end
  end
end
