defmodule Backpex.E2E.SidebarTest do
  use Backpex.E2ECase, async: false

  import Fluffy.Playwright, only: [dispatch_event: 3, evaluate: 2, hover: 2, new_page: 1, route: 3, switch_page: 2]

  alias Fluffy.Playwright.Mouse
  alias Playwright.Request
  alias Playwright.Route

  # LiveView freezes the session at websocket-connect time, so a re-mount
  # after live_redirect inside the same live_session reads a stale cookie
  # and re-renders the sidebar (and its sections) from the default. The
  # hook keeps the user's most recent toggle in sessionStorage and
  # re-asserts it over the stale server render; these tests cover that.

  @blog_toggle ~s|[data-section-id="blog"] [data-menu-dropdown-toggle]|
  @sidebar_toggle ~s|#backpex-sidebar-toggle|
  @invoices_link ~s|a[href="/admin/invoices"]|
  @preferences_url "**/backpex_preferences"

  describe "sidebar section state across live_redirect" do
    test "collapsed section stays collapsed after navigating to a sibling LiveResource", %{session: session} do
      session
      |> visit(~p"/admin/posts")
      |> assert(attribute(by_css(@blog_toggle), "aria-expanded", "true"))
      |> assert_a11y()
      |> click(by_css(@blog_toggle))
      |> assert(attribute(by_css(@blog_toggle), "aria-expanded", "false"))
      |> assert_a11y()
      |> click(by_css(@invoices_link))
      |> assert(page_url(~p"/admin/invoices"))
      |> assert(attribute(by_css(@blog_toggle), "aria-expanded", "false"))
    end
  end

  describe "sidebar open/closed state across live_redirect" do
    # Collapsed sidebar becomes `inert`, so a user-simulated click on a
    # sidebar link can't reach it. Dispatch a click event instead — it
    # bubbles through LiveView's delegated click handler and still
    # triggers the live_redirect.
    test "collapsed sidebar stays collapsed after navigating to a sibling LiveResource", %{session: session} do
      session
      |> visit(~p"/admin/posts")
      |> assert(attribute(by_css(@sidebar_toggle), "aria-expanded", "true"))
      |> assert_a11y()
      |> click(by_css(@sidebar_toggle))
      |> assert(attribute(by_css(@sidebar_toggle), "aria-expanded", "false"))
      |> assert_a11y()
      |> dispatch_event(by_css(@invoices_link), "click")
      |> assert(page_url(~p"/admin/invoices"))
      |> assert(attribute(by_css(@sidebar_toggle), "aria-expanded", "false"))
    end
  end

  describe "sidebar scroll position across navigation" do
    # A short viewport makes the menu scrollable. The link gets a dispatched
    # click because a Playwright click scrolls its target into view.
    @tag Playwright.Test.use(viewport: %{width: 1280, height: 250})
    test "menu keeps its scroll position after live_redirect and reload", %{session: session} do
      menu = by_css("#backpex-sidebar-menu")

      session
      |> visit(~p"/admin/posts")
      |> hover(menu)
      |> Mouse.wheel(0, 100)
      |> assert(js_property(menu, "scrollTop", 100))
      |> dispatch_event(by_css(@invoices_link), "click")
      |> assert(page_url(~p"/admin/invoices"))
      |> assert_has(by_role(:heading, name: "Invoices"))
      |> assert(js_property(menu, "scrollTop", 100))
      |> visit(~p"/admin/posts")
      |> assert(js_property(menu, "scrollTop", 100))
    end
  end

  describe "empty sidebar sections" do
    # Markup no LiveResource of the test app renders: a nested section without items.
    @add_empty_sections """
    () => {
      const parent = document.createElement('li')
      parent.id = 'empty-section-parent'
      parent.className = 'not-has-[[data-sidebar-item]]:hidden'
      parent.innerHTML = `
        <ul>
          <li id="empty-section-child" class="not-has-[[data-sidebar-item]]:hidden">
            <ul id="empty-section-content"></ul>
          </li>
        </ul>
      `
      document.querySelector('#backpex-sidebar').appendChild(parent)
    }
    """

    @add_sidebar_item """
    () => {
      const item = document.createElement('li')
      item.dataset.sidebarItem = ''
      document.querySelector('#empty-section-content').appendChild(item)
    }
    """

    test "CSS hides empty nested sections and reveals them when an item appears", %{session: session} do
      parent = by_css("#empty-section-parent")
      child = by_css("#empty-section-child")

      session
      |> visit(~p"/admin/posts")
      |> tap(&evaluate(&1, @add_empty_sections))
      |> assert(css(parent, "display", "none"))
      |> assert(css(child, "display", "none"))
      |> tap(&evaluate(&1, @add_sidebar_item))
      |> refute(css(parent, "display", "none"))
      |> refute(css(child, "display", "none"))
    end
  end

  describe "preference write ordering" do
    test "serializes sibling Session preferences changed during an active request", %{session: session} do
      session
      |> visit(~p"/admin/posts")
      |> hold_preference_writes()
      |> click(by_css(@blog_toggle))

      assert_receive {:preference_write, first}, 5_000
      assert entries(first) == [%{"key" => "global.sidebar_section.blog", "value" => false}]

      click(session, by_css(@sidebar_toggle))
      # The sidebar write waits behind the request in flight.
      refute_receive {:preference_write, _route}, 500
      Route.continue!(first)

      assert_receive {:preference_write, second}, 5_000
      assert entries(second) == [%{"key" => "global.sidebar_open", "value" => false}]
      Route.continue!(second)

      session
      |> assert_preference_writes_settled()
      |> in_new_tab()
      |> visit(~p"/admin/posts")
      |> assert(attribute(by_css("#backpex-app-shell"), "data-sidebar-open", "false"))
      |> assert(attribute(by_css(~s|[data-section-id="blog"]|), "data-section-open", "false"))
    end

    test "persists the latest intent when the same key changes during a request", %{session: session} do
      session
      |> visit(~p"/admin/posts")
      |> hold_preference_writes()
      |> dispatch_event(theme_radio("dark"), "click")

      assert_receive {:preference_write, first}, 5_000
      assert entries(first) == [%{"key" => "global.theme", "value" => "dark"}]

      dispatch_event(session, theme_radio("cupcake"), "click")
      # The newer theme waits behind the request in flight.
      refute_receive {:preference_write, _route}, 500
      Route.continue!(first)

      assert_receive {:preference_write, second}, 5_000
      assert entries(second) == [%{"key" => "global.theme", "value" => "cupcake"}]
      Route.continue!(second)

      session
      |> assert_preference_writes_settled()
      |> in_new_tab()
      |> visit(~p"/admin/posts")
      |> assert(attribute(by_css("html"), "data-theme", "cupcake"))
      |> assert(checked(theme_radio("cupcake")))
    end
  end

  describe "preference batch rejection" do
    setup do
      prior = Application.get_env(:backpex, Backpex.Preferences)

      Application.put_env(:backpex, Backpex.Preferences,
        adapters: [{:default, Backpex.Test.SelectivelyRejectingSessionPreferencesAdapter, []}]
      )

      on_exit(fn ->
        case prior do
          nil -> Application.delete_env(:backpex, Backpex.Preferences)
          value -> Application.put_env(:backpex, Backpex.Preferences, value)
        end
      end)
    end

    # The three changes are made in one task, so the hook sends them in one batch.
    @change_three_preferences """
    () => {
      document.querySelector('input[name="theme-selector"][value="dark"]').click()
      document.querySelector('#backpex-sidebar-toggle').click()
      document.querySelector('[data-section-id="blog"] [data-menu-dropdown-toggle]').click()
    }
    """

    test "retries unaffected Session writes after the first rejected entry", %{session: session} do
      session
      |> visit(~p"/admin/posts")
      |> hold_preference_writes()
      |> evaluate(@change_three_preferences)

      assert_receive {:preference_write, first}, 5_000

      assert entries(first) == [
               %{"key" => "global.theme", "value" => "dark"},
               %{"key" => "global.sidebar_open", "value" => false},
               %{"key" => "global.sidebar_section.blog", "value" => false}
             ]

      Route.continue!(first)

      assert_receive {:preference_write, second}, 5_000

      assert entries(second) == [
               %{"key" => "global.theme", "value" => "dark"},
               %{"key" => "global.sidebar_section.blog", "value" => false}
             ]

      Route.continue!(second)

      session
      |> assert_preference_writes_settled()
      |> in_new_tab()
      |> visit(~p"/admin/posts")
      |> assert(attribute(by_css("html"), "data-theme", "dark"))
      |> assert(attribute(by_css("#backpex-app-shell"), "data-sidebar-open", "true"))
      |> assert(attribute(by_css(~s|[data-section-id="blog"]|), "data-section-open", "false"))
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

    # The mirror the hook keeps in sessionStorage for live_redirect re-mounts.
    @sidebar_open_mirror """
    () => {
      const manifest = JSON.parse(document.getElementById('backpex-preferences').dataset.preferencesManifest)
      return sessionStorage.getItem(`backpex.prefs.${manifest.routes[0].token}.global.sidebar_open`)
    }
    """

    test "a reload before the preferences POST lands renders the collapsed sidebar", %{session: session} do
      session
      |> visit(~p"/admin/posts")
      |> assert(attribute(by_css(@sidebar_toggle), "aria-expanded", "true"))
      |> hold_preference_writes()
      |> click(by_css(@sidebar_toggle))
      |> assert(attribute(by_css(@sidebar_toggle), "aria-expanded", "false"))

      # The preferences POST is held and never answered.
      assert_receive {:preference_write, _stalled}, 5_000

      # (a) The write is in the cookie, synchronously, before any round trip.
      assert %{value: value} = pending_preferences_cookie(session)
      envelope = value |> URI.decode() |> Jason.decode!()
      assert envelope["version"] == 1
      assert get_in(envelope, ["values", "global.sidebar_open", "value"]) == false
      assert is_binary(get_in(envelope, ["values", "global.sidebar_open", "token"]))

      # A full document GET — same cookies, same dead render, now actually
      # painted. The reloaded page replays the pending write.
      session
      |> assert_event(
        Fluffy.Event.response(&dead_render?/1),
        &visit(&1, ~p"/admin/posts"),
        # (b) THE FLASH ITSELF: the document the browser paints first.
        fn response ->
          html = Playwright.Response.text!(response)
          assert html =~ ~s(data-sidebar-open="false")
          refute html =~ ~s(data-sidebar-open="true")
          refute html =~ "lg:translate-x-0"
        end
      )
      # (c) It lands closed and STAYS closed. Before the fix the hook re-asserted
      # its mount-time `desktopOpen` through the higher-specificity
      # `data-[state]` classes and the page ended up open.
      |> assert(attribute(by_css(@sidebar_toggle), "aria-expanded", "false"))
      |> assert(attribute(by_css("#backpex-sidebar"), "data-state", "closed"))
      |> assert(attribute(by_css("#backpex-main"), "data-shift", "off"))
      |> assert_a11y()

      # The replay goes through.
      assert_receive {:preference_write, replay}, 5_000
      Route.continue!(replay)

      # (d) The pending entry retires on the replay's response: the cookie holds
      # unacknowledged writes only and cannot shadow the adapter.
      assert_preference_writes_settled(session)

      # The mirror survives — it is the live_redirect carrier and has a
      # different job.
      assert evaluate(session, @sidebar_open_mirror) == "false"
    end
  end

  describe "the sidebar transition guard" do
    # `data-suppress-transition` is static markup, so morphdom morphs it back on
    # any patch that re-renders the shell. Only mounted() used to take it off,
    # so the first sort left the sidebar unable to animate for the rest of the
    # page load. live_redirect hides this — it replaces the nodes and re-mounts
    # the hook; the in-place patch is the path that strands the guard.
    test "a live_patch does not strand the transition guard", %{session: session} do
      insert_list(3, :address)

      session
      |> visit(~p"/admin/addresses")
      |> assert_has(by_css("#backpex-sidebar:not([data-suppress-transition])"))
      # Sorting re-renders the shell in place, without re-mounting the hook.
      |> click(by_css(~s|thead a[href*="order_by=street"]|))
      |> assert_has(by_css("#backpex-sidebar:not([data-suppress-transition])"))
      |> assert_has(by_css("#backpex-main:not([data-suppress-transition])"))
    end
  end

  # Holds each preferences request and sends its route to the test, which answers it with `Route.continue!/1`.
  defp hold_preference_writes(session) do
    test = self()
    route(session, @preferences_url, &send(test, {:preference_write, &1}))
  end

  defp entries(route), do: route |> Route.request() |> Request.post_data_json() |> body_entries()

  defp body_entries(%{"preferences" => entries}), do: entries
  defp body_entries(%{"key" => key, "value" => value}), do: [%{"key" => key, "value" => value}]

  defp pending_preferences_cookie(session), do: session |> cookies() |> Enum.find(&(&1.name == "backpex_prefs"))

  # A write retires its pending entry once its response is handled, and the cookie goes with the last one.
  defp assert_preference_writes_settled(session) do
    assert(session, poll(&pending_preferences_cookie/1, &assert(&1 == nil), message: "the preference writes settle"))
  end

  # sessionStorage is per tab, so a new tab renders what the server stored, not the hook's mirror.
  defp in_new_tab(session), do: switch_page(session, new_page(session))

  # The document of the posts index, not a redirect to it.
  defp dead_render?(response) do
    path = response |> Playwright.Response.url() |> URI.parse() |> Map.fetch!(:path)
    path == "/admin/posts" and Playwright.Response.status(response) == 200
  end

  defp theme_radio(theme), do: by_css(~s|input[name="theme-selector"][value="#{theme}"]|)
end
