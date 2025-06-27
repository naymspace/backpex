defmodule DemoWeb.Browser.InvoiceBrowserTest do
  use PhoenixTest.Playwright.Case, async: false
  use DemoWeb, :verified_routes
  use DemoWeb.A11yAssertions

  @moduletag :playwright

  describe "invoices index" do
    test "a11y", %{conn: conn} do
      conn
      |> visit(~p"/admin/invoices")
      |> assert_a11y()
    end
  end
end
