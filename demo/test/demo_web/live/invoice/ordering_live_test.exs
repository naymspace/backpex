defmodule DemoWeb.Live.Invoice.OrderingLiveTest do
  use DemoWeb.ConnCase, async: false

  import Demo.EctoFactory
  import Phoenix.LiveViewTest

  # Invoices use default init_order: %{by: :id, direction: :asc}
  # Invoices are index-only (only: [:index])
  # The factory amount is a Range, so we must provide a concrete integer value
  # Invoices have binary_id (random UUID) primary keys, so ascending id order is
  # unrelated to insertion order and has to be derived from the inserted records.

  describe "default ordering" do
    test "orders by id ascending by default", %{conn: conn} do
      invoices = [
        insert(:invoice, company: "Alpha Corp", amount: 1000),
        insert(:invoice, company: "Beta Inc", amount: 2000),
        insert(:invoice, company: "Gamma LLC", amount: 3000)
      ]

      [first, second, third] = Enum.sort_by(invoices, & &1.id)

      conn
      |> visit(~p"/admin/invoices")
      |> assert_has("table tbody tr", count: 3)
      |> assert_has("table tbody tr:first-child td", text: first.company)
      |> assert_has("table tbody tr:nth-child(2) td", text: second.company)
      |> assert_has("table tbody tr:last-child td", text: third.company)
    end
  end

  describe "ordering via URL params" do
    test "orders by company ascending", %{conn: conn} do
      insert(:invoice, company: "Cherry Corp", amount: 1000)
      insert(:invoice, company: "Apple Inc", amount: 2000)
      insert(:invoice, company: "Banana LLC", amount: 3000)

      params = %{"order_by" => "company", "order_direction" => "asc"}

      conn
      |> visit(~p"/admin/invoices?#{params}")
      |> assert_has("table tbody tr", count: 3)
      |> assert_has("table tbody tr:first-child td", text: "Apple Inc")
      |> assert_has("table tbody tr:last-child td", text: "Cherry Corp")
    end

    test "orders by company descending", %{conn: conn} do
      insert(:invoice, company: "Cherry Corp", amount: 1000)
      insert(:invoice, company: "Apple Inc", amount: 2000)
      insert(:invoice, company: "Banana LLC", amount: 3000)

      params = %{"order_by" => "company", "order_direction" => "desc"}

      conn
      |> visit(~p"/admin/invoices?#{params}")
      |> assert_has("table tbody tr", count: 3)
      |> assert_has("table tbody tr:first-child td", text: "Cherry Corp")
      |> assert_has("table tbody tr:last-child td", text: "Apple Inc")
    end
  end

  describe "invalid ordering params" do
    test "falls back to default order_by for invalid order_by field", %{conn: conn} do
      invoices = [
        insert(:invoice, company: "Alpha Corp", amount: 1000),
        insert(:invoice, company: "Beta Inc", amount: 2000),
        insert(:invoice, company: "Gamma LLC", amount: 3000)
      ]

      [first, second, third] = Enum.sort_by(invoices, & &1.id)

      params = %{"order_by" => "nonexistent_field", "order_direction" => "asc"}

      conn
      |> visit(~p"/admin/invoices?#{params}")
      |> assert_has("table tbody tr", count: 3)
      |> assert_has("table tbody tr:first-child td", text: first.company)
      |> assert_has("table tbody tr:nth-child(2) td", text: second.company)
      |> assert_has("table tbody tr:last-child td", text: third.company)
    end

    test "falls back to default direction for invalid order_direction", %{conn: conn} do
      insert(:invoice, company: "Cherry Corp", amount: 1000)
      insert(:invoice, company: "Apple Inc", amount: 2000)
      insert(:invoice, company: "Banana LLC", amount: 3000)

      params = %{"order_by" => "company", "order_direction" => "INVALID"}

      conn
      |> visit(~p"/admin/invoices?#{params}")
      |> assert_has("table tbody tr", count: 3)
      # order_by=company is valid, direction falls back to default: asc
      |> assert_has("table tbody tr:first-child td", text: "Apple Inc")
      |> assert_has("table tbody tr:last-child td", text: "Cherry Corp")
    end
  end

  describe "ordering via column header click" do
    test "clicking Company column orders by company ascending", %{conn: conn} do
      insert(:invoice, company: "Cherry Corp", amount: 1000)
      insert(:invoice, company: "Apple Inc", amount: 2000)
      insert(:invoice, company: "Banana LLC", amount: 3000)

      conn
      |> visit(~p"/admin/invoices")
      |> unwrap(fn view ->
        view
        |> element("a", "Company")
        |> render_click()
      end)
      |> assert_has("table tbody tr:first-child td", text: "Apple Inc")
      |> assert_has("table tbody tr:last-child td", text: "Cherry Corp")
    end
  end
end
