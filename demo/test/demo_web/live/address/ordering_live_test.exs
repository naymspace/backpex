defmodule DemoWeb.Live.Address.OrderingLiveTest do
  use DemoWeb.ConnCase, async: false

  import Demo.EctoFactory
  import Phoenix.LiveViewTest

  # Addresses use default init_order: %{by: :id, direction: :asc}

  describe "default ordering" do
    test "orders by id ascending by default", %{conn: conn} do
      insert(:address, street: "First Street")
      insert(:address, street: "Second Street")
      insert(:address, street: "Third Street")

      conn
      |> visit(~p"/admin/addresses")
      |> assert_has("table tbody tr", count: 3)
      |> assert_has("table tbody tr:first-child td", text: "First Street")
      |> assert_has("table tbody tr:last-child td", text: "Third Street")
    end
  end

  describe "ordering via URL params" do
    test "orders by street ascending", %{conn: conn} do
      insert(:address, street: "Cherry Lane")
      insert(:address, street: "Apple Street")
      insert(:address, street: "Banana Boulevard")

      params = %{"order_by" => "street", "order_direction" => "asc"}

      conn
      |> visit(~p"/admin/addresses?#{params}")
      |> assert_has("table tbody tr", count: 3)
      |> assert_has("table tbody tr:first-child td", text: "Apple Street")
      |> assert_has("table tbody tr:last-child td", text: "Cherry Lane")
    end

    test "orders by street descending", %{conn: conn} do
      insert(:address, street: "Cherry Lane")
      insert(:address, street: "Apple Street")
      insert(:address, street: "Banana Boulevard")

      params = %{"order_by" => "street", "order_direction" => "desc"}

      conn
      |> visit(~p"/admin/addresses?#{params}")
      |> assert_has("table tbody tr", count: 3)
      |> assert_has("table tbody tr:first-child td", text: "Cherry Lane")
      |> assert_has("table tbody tr:last-child td", text: "Apple Street")
    end

    test "orders by city ascending", %{conn: conn} do
      insert(:address, street: "Street C", city: "Zurich")
      insert(:address, street: "Street A", city: "Berlin")
      insert(:address, street: "Street B", city: "Munich")

      params = %{"order_by" => "city", "order_direction" => "asc"}

      conn
      |> visit(~p"/admin/addresses?#{params}")
      |> assert_has("table tbody tr", count: 3)
      |> assert_has("table tbody tr:first-child td", text: "Street A")
      |> assert_has("table tbody tr:last-child td", text: "Street C")
    end
  end

  describe "invalid ordering params" do
    test "falls back to default order_by for invalid order_by field", %{conn: conn} do
      insert(:address, street: "First Street")
      insert(:address, street: "Second Street")
      insert(:address, street: "Third Street")

      params = %{"order_by" => "nonexistent_field", "order_direction" => "asc"}

      conn
      |> visit(~p"/admin/addresses?#{params}")
      |> assert_has("table tbody tr", count: 3)
      |> assert_has("table tbody tr:first-child td", text: "First Street")
      |> assert_has("table tbody tr:last-child td", text: "Third Street")
    end

    test "falls back to default direction for invalid order_direction", %{conn: conn} do
      insert(:address, street: "Cherry Lane")
      insert(:address, street: "Apple Street")
      insert(:address, street: "Banana Boulevard")

      params = %{"order_by" => "street", "order_direction" => "INVALID"}

      conn
      |> visit(~p"/admin/addresses?#{params}")
      |> assert_has("table tbody tr", count: 3)
      # order_by=street is valid, direction falls back to default: asc
      |> assert_has("table tbody tr:first-child td", text: "Apple Street")
      |> assert_has("table tbody tr:last-child td", text: "Cherry Lane")
    end
  end

  describe "ordering via column header click" do
    test "clicking Street Name column orders by street ascending", %{conn: conn} do
      insert(:address, street: "Cherry Lane")
      insert(:address, street: "Apple Street")
      insert(:address, street: "Banana Boulevard")

      conn
      |> visit(~p"/admin/addresses")
      |> unwrap(fn view ->
        view
        |> element("a", "Street Name")
        |> render_click()
      end)
      |> assert_has("table tbody tr:first-child td", text: "Apple Street")
      |> assert_has("table tbody tr:last-child td", text: "Cherry Lane")
    end
  end
end
