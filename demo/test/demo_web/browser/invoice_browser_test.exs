defmodule DemoWeb.Browser.InvoiceBrowserTest do
  use DemoWeb.BrowserCase, async: false
  use DemoWeb, :verified_routes
  use DemoWeb.A11yAssertions

  @moduletag :playwright

  describe "invoices index" do
    test "a11y", %{session: session} do
      session
      |> visit(~p"/admin/invoices")
      |> assert_a11y()
    end
  end
end
