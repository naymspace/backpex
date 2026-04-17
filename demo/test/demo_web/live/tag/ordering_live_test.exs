defmodule DemoWeb.Live.Tag.OrderingLiveTest do
  use DemoWeb.ConnCase, async: false

  import Demo.EctoFactory
  import Phoenix.LiveViewTest

  # Tags have init_order: %{by: :name, direction: :desc}

  describe "default ordering" do
    test "orders by name descending by default", %{conn: conn} do
      insert(:tag, name: "Alpha")
      insert(:tag, name: "Beta")
      insert(:tag, name: "Gamma")

      conn
      |> visit(~p"/admin/tags")
      |> assert_has("table tbody tr", count: 3)
      |> assert_has("table tbody tr:first-child td", text: "Gamma")
      |> assert_has("table tbody tr:last-child td", text: "Alpha")
    end
  end

  describe "ordering via URL params" do
    test "orders by name ascending when order_direction=asc", %{conn: conn} do
      insert(:tag, name: "Alpha")
      insert(:tag, name: "Beta")
      insert(:tag, name: "Gamma")

      params = %{"order_by" => "name", "order_direction" => "asc"}

      conn
      |> visit(~p"/admin/tags?#{params}")
      |> assert_has("table tbody tr", count: 3)
      |> assert_has("table tbody tr:first-child td", text: "Alpha")
      |> assert_has("table tbody tr:last-child td", text: "Gamma")
    end

    test "orders by name descending via explicit param", %{conn: conn} do
      insert(:tag, name: "Alpha")
      insert(:tag, name: "Beta")
      insert(:tag, name: "Gamma")

      params = %{"order_by" => "name", "order_direction" => "desc"}

      conn
      |> visit(~p"/admin/tags?#{params}")
      |> assert_has("table tbody tr", count: 3)
      |> assert_has("table tbody tr:first-child td", text: "Gamma")
      |> assert_has("table tbody tr:last-child td", text: "Alpha")
    end
  end

  describe "invalid ordering params" do
    test "falls back to default order_by for invalid order_by field", %{conn: conn} do
      insert(:tag, name: "Alpha")
      insert(:tag, name: "Beta")
      insert(:tag, name: "Gamma")

      # order_by falls back to init_order.by (:name), direction stays as provided (:asc)
      params = %{"order_by" => "nonexistent_field", "order_direction" => "asc"}

      conn
      |> visit(~p"/admin/tags?#{params}")
      |> assert_has("table tbody tr", count: 3)
      |> assert_has("table tbody tr:first-child td", text: "Alpha")
      |> assert_has("table tbody tr:last-child td", text: "Gamma")
    end

    test "falls back to full default order when both params are invalid", %{conn: conn} do
      insert(:tag, name: "Alpha")
      insert(:tag, name: "Beta")
      insert(:tag, name: "Gamma")

      params = %{"order_by" => "nonexistent_field", "order_direction" => "invalid"}

      conn
      |> visit(~p"/admin/tags?#{params}")
      |> assert_has("table tbody tr", count: 3)
      # Falls back to init_order: name desc
      |> assert_has("table tbody tr:first-child td", text: "Gamma")
      |> assert_has("table tbody tr:last-child td", text: "Alpha")
    end

    test "falls back to default direction for invalid order_direction", %{conn: conn} do
      insert(:tag, name: "Alpha")
      insert(:tag, name: "Beta")
      insert(:tag, name: "Gamma")

      params = %{"order_by" => "name", "order_direction" => "invalid"}

      conn
      |> visit(~p"/admin/tags?#{params}")
      |> assert_has("table tbody tr", count: 3)
      # Falls back to init_order direction: desc
      |> assert_has("table tbody tr:first-child td", text: "Gamma")
      |> assert_has("table tbody tr:last-child td", text: "Alpha")
    end
  end

  describe "ordering via column header click" do
    test "clicking name column toggles order direction", %{conn: conn} do
      insert(:tag, name: "Alpha")
      insert(:tag, name: "Beta")
      insert(:tag, name: "Gamma")

      conn
      |> visit(~p"/admin/tags")
      # Default is name desc
      |> assert_has("table tbody tr:first-child td", text: "Gamma")
      # Click name column to toggle to asc
      |> unwrap(fn view ->
        view
        |> element("a", "Name")
        |> render_click()
      end)
      |> assert_has("table tbody tr:first-child td", text: "Alpha")
      |> assert_has("table tbody tr:last-child td", text: "Gamma")
    end

    test "clicking same column twice returns to original direction", %{conn: conn} do
      insert(:tag, name: "Alpha")
      insert(:tag, name: "Beta")
      insert(:tag, name: "Gamma")

      conn
      |> visit(~p"/admin/tags")
      # Default is name desc
      |> assert_has("table tbody tr:first-child td", text: "Gamma")
      # Click name to toggle to asc
      |> unwrap(fn view ->
        view
        |> element("a", "Name")
        |> render_click()
      end)
      |> assert_has("table tbody tr:first-child td", text: "Alpha")
      # Click name again to toggle back to desc
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
