defmodule DemoWeb.Browser.SidebarBrowserTest do
  use PhoenixTest.Playwright.Case, async: false
  use DemoWeb, :verified_routes

  @moduletag :playwright

  # Regression test for the bug where a collapsed sidebar_section reverts to
  # its server-rendered default on a live_redirect inside the same
  # live_session. LiveView freezes the session at websocket-connect time, so
  # the re-mount reads a stale cookie, re-renders the section as open, and
  # (pre-fix) nothing on the client re-asserts the user's collapsed state.

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
    # click handler and triggers the same live_redirect, which is what
    # the regression is about.
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
