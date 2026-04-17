defmodule DemoWeb.Live.Category.OrderingLiveTest do
  use DemoWeb.ConnCase, async: false

  import Demo.EctoFactory
  import Phoenix.LiveViewTest

  # Categories have init_order: %{by: :name, direction: :asc}

  describe "default ordering" do
    test "orders by name ascending by default", %{conn: conn} do
      insert(:category, name: "Alpha")
      insert(:category, name: "Beta")
      insert(:category, name: "Gamma")

      conn
      |> visit(~p"/admin/categories")
      |> assert_has("table tbody tr", count: 3)
      |> assert_has("table tbody tr:first-child td", text: "Alpha")
      |> assert_has("table tbody tr:last-child td", text: "Gamma")
    end
  end

  describe "ordering via URL params" do
    test "orders by name descending", %{conn: conn} do
      insert(:category, name: "Alpha")
      insert(:category, name: "Beta")
      insert(:category, name: "Gamma")

      params = %{"order_by" => "name", "order_direction" => "desc"}

      conn
      |> visit(~p"/admin/categories?#{params}")
      |> assert_has("table tbody tr", count: 3)
      |> assert_has("table tbody tr:first-child td", text: "Gamma")
      |> assert_has("table tbody tr:last-child td", text: "Alpha")
    end

    test "orders by name ascending via explicit param", %{conn: conn} do
      insert(:category, name: "Alpha")
      insert(:category, name: "Beta")
      insert(:category, name: "Gamma")

      params = %{"order_by" => "name", "order_direction" => "asc"}

      conn
      |> visit(~p"/admin/categories?#{params}")
      |> assert_has("table tbody tr", count: 3)
      |> assert_has("table tbody tr:first-child td", text: "Alpha")
      |> assert_has("table tbody tr:last-child td", text: "Gamma")
    end
  end

  describe "invalid ordering params" do
    test "falls back to default order_by for invalid order_by field", %{conn: conn} do
      insert(:category, name: "Alpha")
      insert(:category, name: "Beta")
      insert(:category, name: "Gamma")

      # order_by falls back to init_order.by (:name), direction stays as provided (:desc)
      params = %{"order_by" => "nonexistent_field", "order_direction" => "desc"}

      conn
      |> visit(~p"/admin/categories?#{params}")
      |> assert_has("table tbody tr", count: 3)
      |> assert_has("table tbody tr:first-child td", text: "Gamma")
      |> assert_has("table tbody tr:last-child td", text: "Alpha")
    end

    test "falls back to default direction for invalid order_direction", %{conn: conn} do
      insert(:category, name: "Alpha")
      insert(:category, name: "Beta")
      insert(:category, name: "Gamma")

      params = %{"order_by" => "name", "order_direction" => "invalid"}

      conn
      |> visit(~p"/admin/categories?#{params}")
      |> assert_has("table tbody tr", count: 3)
      # Falls back to init_order direction: asc
      |> assert_has("table tbody tr:first-child td", text: "Alpha")
      |> assert_has("table tbody tr:last-child td", text: "Gamma")
    end
  end

  describe "ordering via column header click" do
    test "clicking name column toggles to descending", %{conn: conn} do
      insert(:category, name: "Alpha")
      insert(:category, name: "Beta")
      insert(:category, name: "Gamma")

      conn
      |> visit(~p"/admin/categories")
      # Default is name asc
      |> assert_has("table tbody tr:first-child td", text: "Alpha")
      # Click name column to toggle to desc
      |> unwrap(fn view ->
        view
        |> element("a", "Name")
        |> render_click()
      end)
      |> assert_has("table tbody tr:first-child td", text: "Gamma")
      |> assert_has("table tbody tr:last-child td", text: "Alpha")
    end
  end
end
