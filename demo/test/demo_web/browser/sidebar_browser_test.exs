defmodule DemoWeb.Browser.SidebarBrowserTest do
  use PhoenixTest.Playwright.Case, async: false
  use DemoWeb, :verified_routes

  @moduletag :playwright

  # LiveView freezes the session at websocket-connect time, so a re-mount
  # after live_redirect inside the same live_session reads a stale cookie
  # and re-renders the sidebar (and its sections) from the default. The
  # hook keeps the user's most recent toggle in sessionStorage and
  # re-asserts it over the stale server render; these tests cover that.

  @blog_toggle ~s|[data-section-id="blog"] [data-menu-dropdown-toggle]|
  @sidebar_toggle ~s|#backpex-sidebar-toggle|

  describe "sidebar section state across live_redirect" do
    test "collapsed section stays collapsed after navigating to a sibling LiveResource", %{conn: conn} do
      conn
      |> visit(~p"/admin/posts")
      |> assert_has("body .phx-connected")
      |> assert_has(~s|#{@blog_toggle}[aria-expanded="true"]|)
      |> click(@blog_toggle)
      |> assert_has(~s|#{@blog_toggle}[aria-expanded="false"]|)
      |> click(~s|a[href="/admin/invoices"]|)
      |> assert_path("/admin/invoices")
      |> assert_has(~s|#{@blog_toggle}[aria-expanded="false"]|)
    end
  end

  describe "sidebar open/closed state across live_redirect" do
    # Collapsed sidebar becomes `inert`, so a user-simulated click on a
    # sidebar link can't reach it. Fire a programmatic click via
    # `HTMLElement.click()` — it bubbles through LiveView's delegated
    # click handler and still triggers the live_redirect.
    test "collapsed sidebar stays collapsed after navigating to a sibling LiveResource", %{conn: conn} do
      conn
      |> visit(~p"/admin/posts")
      |> assert_has("body .phx-connected")
      |> assert_has(~s|#{@sidebar_toggle}[aria-expanded="true"]|)
      |> click(@sidebar_toggle)
      |> assert_has(~s|#{@sidebar_toggle}[aria-expanded="false"]|)
      |> evaluate(~s|document.querySelector('a[href="/admin/invoices"]').click()|)
      |> assert_path("/admin/invoices")
      |> assert_has(~s|#{@sidebar_toggle}[aria-expanded="false"]|)
    end
  end
end
