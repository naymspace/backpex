defmodule DemoWeb.TicketLiveTest do
  use DemoWeb.ConnCase, async: false

  import Demo.AshFactory
  import Demo.Support.LiveResourceTests
  import Phoenix.LiveViewTest

  alias Demo.Helpdesk.Ticket

  describe "tickets live resource index" do
    test "is rendered", %{conn: conn} do
      insert!(Ticket, count: 3)

      conn
      |> visit(~p"/admin/tickets")
      |> assert_has("h1", text: "Tickets", exact: true)
      |> assert_has("button[disabled]", text: "Delete", exact: true)
      |> assert_has("div", text: "Items 1 to 3 (3 total)", exact: true)
      |> assert_has("table tbody tr", count: 3)
    end

    test "basic functionality", %{conn: conn} do
      tickets = insert!(Ticket, count: 3)

      test_table_rows_count(conn, ~p"/admin/tickets", Enum.count(tickets))
      test_delete_button_disabled_enabled(conn, ~p"/admin/tickets", tickets)
      test_show_action_redirect(conn, ~p"/admin/tickets", tickets)
    end
  end

  describe "tickets live resource show" do
    test "is rendered", %{conn: conn} do
      ticket = insert!(Ticket)

      conn
      |> visit(~p"/admin/tickets/#{ticket.id}/show")
      |> assert_has("h1", text: "Ticket", exact: true)
      |> assert_has("p", text: "Subject", exact: true)
      |> assert_has("p", text: "Body", exact: true)
      |> assert_has("p", text: ticket.subject, exact: true)
      |> assert_has("p", text: ticket.body, exact: true)
    end
  end
end
