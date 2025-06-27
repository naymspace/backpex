defmodule DemoWeb.Browser.TicketBrowserTest do
  use PhoenixTest.Playwright.Case, async: false
  use DemoWeb, :verified_routes
  use DemoWeb.A11yAssertions

  import Demo.AshFactory

  alias Demo.Helpdesk.Ticket

  @moduletag :playwright

  describe "tickets index" do
    test "a11y", %{conn: conn} do
      insert!(Ticket, count: 10)

      conn
      |> visit(~p"/admin/tickets")
      |> assert_a11y()
    end
  end

  describe "tickets show" do
    test "a11y", %{conn: conn} do
       ticket = insert!(Ticket)

      conn
      |> visit(~p"/admin/tickets/#{ticket.id}/show")
      |> assert_a11y()
    end
  end
end
