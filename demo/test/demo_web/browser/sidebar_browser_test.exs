defmodule DemoWeb.Browser.SidebarBrowserTest do
  use PhoenixTest.Playwright.Case, async: false
  use DemoWeb, :verified_routes
  use DemoWeb.A11yAssertions

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
      |> assert_a11y()
      |> click(@blog_toggle)
      |> assert_has(~s|#{@blog_toggle}[aria-expanded="false"]|)
      |> assert_a11y()
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
      |> assert_a11y()
      |> click(@sidebar_toggle)
      |> assert_has(~s|#{@sidebar_toggle}[aria-expanded="false"]|)
      |> assert_a11y()
      |> evaluate(~s|document.querySelector('a[href="/admin/invoices"]').click()|)
      |> assert_path("/admin/invoices")
      |> assert_has(~s|#{@sidebar_toggle}[aria-expanded="false"]|)
    end
  end

  describe "quick reload inside the persist race window" do
    # The bug, reproduced deterministically. The preferences POST is stalled so
    # the server NEVER sees the toggle: the session cookie stays "sidebar open"
    # for the whole test. That is exactly the state a real browser is in for the
    # ~1.1s between the click and the POST's Set-Cookie, and any reload landing
    # in that window used to paint the OLD sidebar and then flip.
    #
    # Everything the fix has to do is therefore observable here:
    #   1. the toggle is recorded in the `backpex_prefs` cookie synchronously;
    #   2. a document GET made in that state already renders the CLOSED sidebar
    #      (assertion (b) — the literal bytes the browser paints first, which is
    #      what the flash is, and it is not subject to paint-timing flakiness);
    #   3. after the reload the page STAYS closed instead of being stomped back
    #      open by the hook's once-cached `desktopOpen` (aggravating factor B);
    #   4. once the POST is allowed through, the pending entry retires and the
    #      cookie disappears, so it can never become a second store.

    # Stall the preferences POST only. Every other request (including the
    # document fetch below) goes through the original `fetch`, which we stash on
    # `window` so the test can still make one.
    @stall_preferences """
    () => {
      window.__originalFetch = window.fetch.bind(window)
      window.fetch = (input, opts) => {
        const url = typeof input === 'string' ? input : input.url
        if (url.includes('backpex_preferences')) return new Promise(() => {})
        return window.__originalFetch(input, opts)
      }
      return true
    }
    """

    # The bytes a hard reload would paint, fetched in the state the click left
    # the browser in: stale session cookie + fresh `backpex_prefs` cookie.
    @fetch_dead_render """
    async () => {
      const response = await window.__originalFetch(location.href, { cache: 'no-store' })
      return await response.text()
    }
    """

    # `replayPending()` re-POSTs the write on the next page load; the response
    # retires the entry. Poll rather than sleep so the test does not encode the
    # round-trip time.
    @await_cookie_retired """
    async () => {
      for (let i = 0; i < 50; i++) {
        if (!document.cookie.includes('backpex_prefs')) return 'retired'
        await new Promise((resolve) => setTimeout(resolve, 100))
      }
      return document.cookie
    }
    """

    test "a reload before the preferences POST lands renders the collapsed sidebar", %{conn: conn} do
      conn
      |> visit(~p"/admin/posts")
      |> assert_has("body .phx-connected")
      |> assert_has(~s|#{@sidebar_toggle}[aria-expanded="true"]|)
      |> evaluate(@stall_preferences, is_function: true)
      |> click(@sidebar_toggle)
      |> assert_has(~s|#{@sidebar_toggle}[aria-expanded="false"]|)
      # (a) The write is in the cookie, synchronously, before any round trip.
      |> evaluate("document.cookie", fn cookie ->
        assert cookie =~ "backpex_prefs"
        assert URI.decode(cookie) =~ ~s("global.sidebar_open":false)
      end)
      # (b) THE FLASH ITSELF: the document the browser would paint first.
      |> evaluate(@fetch_dead_render, [is_function: true], fn html ->
        assert html =~ ~s(data-sidebar-open="false")
        refute html =~ ~s(data-sidebar-open="true")
        refute html =~ "lg:translate-x-0"
      end)
      # A full document GET — same cookies, same dead render, now actually
      # painted. The stalled `fetch` stub dies with the old document, so the
      # reloaded page replays the pending write for real.
      |> visit(~p"/admin/posts")
      |> assert_has("body .phx-connected")
      # (c) It lands closed and STAYS closed. Before the fix the hook re-asserted
      # its mount-time `desktopOpen` through the higher-specificity
      # `data-[state]` classes and the page ended up open.
      |> assert_has(~s|#{@sidebar_toggle}[aria-expanded="false"]|)
      |> assert_has(~s|#backpex-sidebar[data-state="closed"]|)
      |> assert_has(~s|#backpex-main[data-shift="off"]|)
      |> assert_a11y()
      # (d) The pending entry retires on the replay's response: the cookie holds
      # unacknowledged writes only and cannot shadow the adapter.
      |> evaluate(@await_cookie_retired, [is_function: true], fn result ->
        assert result == "retired"
      end)
      # The mirror survives — it is the live_redirect carrier and has a
      # different job.
      |> evaluate("sessionStorage.getItem('backpex.prefs.global.sidebar_open')", fn value ->
        assert value == "false"
      end)
    end
  end
end
