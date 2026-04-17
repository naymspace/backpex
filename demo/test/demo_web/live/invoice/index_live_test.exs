defmodule DemoWeb.Live.Invoice.IndexLiveTest do
  use DemoWeb.ConnCase, async: false

  import Demo.EctoFactory

  describe "invoices live resource index" do
    setup do
      invoice1 = insert(:invoice, company: "Acme Corp", amount: 150_000)
      invoice2 = insert(:invoice, company: "Tech Inc", amount: 250_000)
      invoice3 = insert(:invoice, company: "Global Ltd", amount: 350_000)

      %{invoices: [invoice1, invoice2, invoice3]}
    end

    test "is rendered", %{conn: conn, invoices: invoices} do
      conn
      |> visit(~p"/admin/invoices")
      |> assert_has("h1", text: "Invoices", exact: true)
      |> assert_has("table tbody tr", count: Enum.count(invoices))
    end

    test "renders invoice with company name", %{conn: conn} do
      conn
      |> visit(~p"/admin/invoices")
      |> assert_has("td", text: "Acme Corp")
    end

    test "no new button available (read-only resource)", %{conn: conn} do
      conn
      |> visit(~p"/admin/invoices")
      |> refute_has("button", text: "New Invoice")
    end

    test "no edit action available", %{conn: conn, invoices: [invoice | _]} do
      conn
      |> visit(~p"/admin/invoices")
      |> refute_has("#item-action-edit-#{invoice.id}")
    end

    test "no delete action available", %{conn: conn, invoices: [invoice | _]} do
      conn
      |> visit(~p"/admin/invoices")
      |> refute_has("button[aria-label='Delete'][phx-value-item-id='#{invoice.id}']")
    end

    test "show action is not available (index-only resource)", %{conn: conn, invoices: [invoice | _]} do
      conn
      |> visit(~p"/admin/invoices")
      # Show action is not available because routes are only: [:index]
      |> refute_has("#item-action-show-#{invoice.id}")
    end

    test "currency field formats amount correctly", %{conn: conn} do
      conn
      |> visit(~p"/admin/invoices")
      # Amount 150000 should be displayed as formatted currency (1,500.00 or similar)
      |> assert_has("td", text: "1,500")
    end
  end
end
