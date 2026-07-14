defmodule DemoWeb.Live.PreferencesPersistenceTest do
  @moduledoc """
  End-to-end coverage for the `persist: [:order, :filters, :columns]` option on
  `Backpex.LiveResource`. Mounts `DemoWeb.PostLive` (configured with all three
  persistence kinds) and asserts that sort, filter, and column-toggle
  interactions emit a `push_event` with the expected preference key and value
  shape.

  The wire event name comes from `Backpex.Preferences.LiveView.event_name/0`
  and the keys come from `Backpex.Preferences.Keys.{order,filters,columns}/1`,
  so the test reflects the same contract the emitter uses.
  """

  use DemoWeb.ConnCase, async: false

  import Demo.EctoFactory
  import Phoenix.LiveViewTest

  alias Backpex.Preferences.Context
  alias Backpex.Preferences.Keys, as: PrefKeys
  alias Backpex.Preferences.LiveView, as: PrefLiveView

  @resource_mod DemoWeb.PostLive

  # assert_push_event expands to assert_receive, which pattern-matches the
  # arguments. Bind the event name and key to module-level constants or local
  # variables before the macro call so the pattern is literal-shaped.
  @event_name PrefLiveView.event_name()

  # The shape `Plug.CSRFProtection` generates (18 random bytes, base64url).
  @csrf_token "0hs7B3xF1qLmNpQrStUvWx"

  describe "persist: [:order]" do
    test "sort change via column-header click emits push_event with order key", %{conn: conn} do
      insert(:post, title: "Alpha", published: true)
      insert(:post, title: "Beta", published: true)

      {:ok, view, _html} = live(conn, ~p"/admin/posts?filters[published][]=published")

      # Click the Title column header — triggers a sort and routes through
      # maybe_persist_order/2 which fires the push_event.
      view
      |> element("a", "Title")
      |> render_click()

      expected_key = PrefKeys.order(@resource_mod)

      assert_push_event(view, @event_name, %{
        key: ^expected_key,
        value: %{"by" => "title", "direction" => "asc"}
      })
    end
  end

  describe "persist: [:filters]" do
    test "filter change emits push_event with filters key", %{conn: conn} do
      insert(:post, title: "Published", published: true)
      insert(:post, title: "Draft", published: false)

      # Mount with the default published-only filter applied.
      {:ok, view, _html} = live(conn, ~p"/admin/posts?filters[published][]=published")

      # Toggle the filter to include not_published too — routes through
      # the change-filter handler → apply_filter_change/2 → push_event.
      view
      |> form("form[phx-change='change-filter']",
        filters: %{published: ["published", "not_published"]}
      )
      |> render_change()

      expected_key = PrefKeys.filters(@resource_mod)

      # The LiveResource emits several filter-persistence events over the mount
      # + change cycle. We care that at least one of them reflects the new
      # two-value set and carries the filters key.
      assert_push_event(view, @event_name, %{
        key: ^expected_key,
        value: %{"published" => ["published", "not_published"]}
      })
    end

    test "clear-filter emits push_event with empty map", %{conn: conn} do
      insert(:post, title: "Published", published: true)
      insert(:post, title: "Draft", published: false)

      # Mount with the default published-only filter applied.
      {:ok, view, _html} = live(conn, ~p"/admin/posts?filters[published][]=published")

      # Click the filter badge's clear (×) button for the `published` filter.
      # The URL collapses to no `filters[]` param, so the clear-filter handler
      # itself must emit the empty-map push_event — apply_index can't infer the
      # cleared intent from the URL alone.
      #
      # There are two buttons that fire `clear-filter` for the same field
      # (the inline "clear" link and the indicator badge's × icon). Target
      # the indicator explicitly via its aria-label.
      view
      |> element("button[aria-label='Clear Published? filter']")
      |> render_click()

      expected_key = PrefKeys.filters(@resource_mod)

      assert_push_event(view, @event_name, %{key: ^expected_key, value: value})
      assert value == %{}
    end

    test "persisted %{} filters suppress redirect to defaults on mount", %{conn: conn} do
      # Simulates the round-trip after a user cleared every filter and
      # navigated away: the preferences adapter holds an explicit empty map.
      # On return, `apply_index` must treat that state as "user cleared
      # everything" and skip the default-filter redirect. Without this,
      # `maybe_redirect_to_default_filters` would see `query_options.filters
      # == %{}` and re-apply the `:default` from the `published` filter,
      # overwriting the user's persisted clear.
      insert(:post, title: "Published Post", published: true)
      insert(:post, title: "Draft Post", published: false)

      session = %{
        "backpex_preferences" => %{
          "resource" => %{"DemoWeb.PostLive" => %{"filters" => %{}}}
        }
      }

      conn = Plug.Test.init_test_session(conn, session)

      {:ok, _view, html} = live(conn, ~p"/admin/posts")

      # Both posts are visible → no `published` default was applied.
      assert html =~ "Published Post"
      assert html =~ "Draft Post"
    end

    test "no persisted filters still triggers redirect to defaults on mount", %{conn: conn} do
      # Pins the existing onboarding flow: a fresh user with nothing in the
      # preferences store still gets the `:default` filter applied (and the
      # URL rewritten to carry it), so the bug fix doesn't regress this path.
      insert(:post, title: "Published Post", published: true)
      insert(:post, title: "Draft Post", published: false)

      assert {:error, {:live_redirect, %{to: to}}} = live(conn, ~p"/admin/posts")
      assert to =~ "filters[published][]=published"
    end
  end

  describe "persist: [:columns]" do
    test "column toggle emits push_event with columns key", %{conn: conn} do
      insert(:post, title: "Alpha", published: true)

      {:ok, view, _html} = live(conn, ~p"/admin/posts?filters[published][]=published")

      # Toggle the "title" column off. maybe_push_columns/3 emits the
      # push_event with the full active-fields map.
      view
      |> element("input[phx-click='toggle_column'][phx-value-field='title']")
      |> render_click()

      expected_key = PrefKeys.columns(@resource_mod)

      assert_push_event(view, @event_name, %{key: ^expected_key, value: value})

      # title was just toggled, so it must now be false; other fields remain true.
      assert is_map(value)
      assert value["title"] == false
    end
  end

  describe "dead render with an unacknowledged client write" do
    # These are the only assertions in the suite that look at the bytes the
    # browser paints FIRST. They use `get/2`, not `live/2`, so what they render
    # is the DISCONNECTED mount — the document response to a hard reload.
    #
    # The scenario: the user toggled a preference and reloaded before the
    # keepalive POST's `Set-Cookie` reached the cookie jar. The session this GET
    # carries is one round-trip stale, so the adapter would render the PRE-toggle
    # state and LiveView would patch it away a frame later. That patch is the
    # flash. The browser's synchronously-written `backpex_prefs` cookie rides
    # this request and must win.
    #
    # If the disconnected branch of `Backpex.Preferences.LiveView` ever stops
    # working, these fail and nothing else in the suite does: a `live/2` test
    # cannot see this, because its connect params already carry the overlay.

    # The wire format the JS hook writes: encodeURIComponent(JSON.stringify(envelope)),
    # where the envelope stamps the pending writes with the identity fingerprint the
    # server rendered into `data-preferences-identity`. Stamped by default with the
    # identity of the very request being made — the browser wrote it while looking at
    # a page rendered for this same user.
    defp put_pending_writes(conn, writes, identity \\ nil) do
      fingerprint = identity || fingerprint(Plug.Conn.get_session(conn))

      encoded =
        %{"id" => fingerprint, "values" => writes}
        |> Jason.encode!()
        |> URI.encode(&URI.char_unreserved?/1)

      Plug.Test.put_req_cookie(conn, PrefLiveView.client_cookie(), encoded)
    end

    # Every request of a session but its very first carries a CSRF token, and the
    # fingerprint needs it: it is what scopes the session-backed preference store.
    defp stale_session(conn, preferences, csrf_token \\ @csrf_token) do
      Plug.Test.init_test_session(conn, %{
        "_csrf_token" => csrf_token,
        "backpex_preferences" => preferences
      })
    end

    defp fingerprint(session) do
      session
      |> Context.from_mount()
      |> PrefLiveView.identity_fingerprint(DemoWeb.Endpoint)
    end

    test "sidebar renders closed even though the session still says open", %{conn: conn} do
      insert(:post, title: "Alpha", published: true)

      conn =
        conn
        |> stale_session(%{"global" => %{"sidebar_open" => true}})
        |> put_pending_writes(%{"global.sidebar_open" => false})
        |> get(~p"/admin/posts?filters[published][]=published")

      html = html_response(conn, 200)

      # `data-sidebar-open` drives the hook's mount-time seed, and
      # `lg:translate-x-0` is what makes the sidebar visible on desktop at first
      # paint. Both must already reflect the user's toggle.
      assert html =~ ~s(data-sidebar-open="false")
      refute html =~ ~s(data-sidebar-open="true")
      refute html =~ "lg:translate-x-0"
    end

    test "sidebar renders open from the session when nothing is pending", %{conn: conn} do
      # The control for the case above: without a pending write the adapter is
      # authoritative, so the cookie cannot be shadowing anything.
      insert(:post, title: "Alpha", published: true)

      conn =
        conn
        |> stale_session(%{"global" => %{"sidebar_open" => true}})
        |> get(~p"/admin/posts?filters[published][]=published")

      html = html_response(conn, 200)

      assert html =~ ~s(data-sidebar-open="true")
      assert html =~ "lg:translate-x-0"
    end

    test "a hidden column is absent from the dead render's table", %{conn: conn} do
      # The half of the problem no pre-paint script could ever fix: chrome can be
      # corrected from a `<head>` script, but a table that was already streamed
      # with the wrong columns cannot. The server has to render it right.
      insert(:post, title: "Alpha", published: true)

      columns_key = PrefKeys.columns(@resource_mod)

      conn =
        conn
        |> stale_session(%{
          "resource" => %{"DemoWeb.PostLive" => %{"columns" => %{"title" => true}}}
        })
        |> put_pending_writes(%{columns_key => %{"title" => false}})
        |> get(~p"/admin/posts?filters[published][]=published")

      html = html_response(conn, 200)

      # The Title column's `<th>` carries the sort link; hiding the column drops
      # the whole cell. The toggle-columns dropdown still lists `title`, so key
      # the assertion on the order link, which only the header renders.
      refute html =~ "order_by=title"

      # Guards against a vacuous `refute`: the table's other columns still render
      # their sort links, and `title` still appears in the column-visibility
      # dropdown (which lists every field, active or not).
      assert html =~ "order_by=likes"
      assert html =~ ~s(phx-value-field="title")
    end

    test "a visible column is present in the dead render's table", %{conn: conn} do
      insert(:post, title: "Alpha", published: true)

      conn =
        conn
        |> stale_session(%{
          "resource" => %{"DemoWeb.PostLive" => %{"columns" => %{"title" => false}}}
        })
        |> put_pending_writes(%{PrefKeys.columns(@resource_mod) => %{"title" => true}})
        |> get(~p"/admin/posts?filters[published][]=published")

      html = html_response(conn, 200)

      # Symmetry check: the cookie can also turn a column back ON against a
      # session that hides it — the overlay is a real overlay, not a mask.
      assert html =~ "order_by=title"
    end

    test "the root layout's data-theme reflects the pending theme write", %{conn: conn} do
      # `<html data-theme>` is rendered from `assigns[:current_theme]`, which
      # InitAssigns reads at mount. A stale theme here is the most visible flash
      # of all: the whole page repaints.
      insert(:post, title: "Alpha", published: true)

      conn =
        conn
        |> stale_session(%{"global" => %{"theme" => "light"}})
        |> put_pending_writes(%{PrefKeys.theme() => "dark"})
        |> get(~p"/admin/posts?filters[published][]=published")

      html = html_response(conn, 200)

      assert html =~ ~s(data-theme="dark")
      refute html =~ ~s(data-theme="light")
    end

    test "a wrong-typed value in the cookie does not crash the dead render", %{conn: conn} do
      # `backpex_prefs` is non-HttpOnly (it has to be: only JS can write it
      # synchronously), unsigned, path=/ and shared across tabs, so any script on
      # the origin can plant one. A browser-written value must therefore never
      # decide whether the page renders at all: `{"global.sidebar_open": "false"}`
      # — a JSON *string*, not a boolean — would reach `inert={not @sidebar_open}`
      # in `Backpex.HTML.Layout.app_shell/1`, and `not "false"` raises, turning a
      # single planted cookie into an HTTP 500 on every page until it expires.
      #
      # `Context.put_client/2` drops it: the value fails
      # `Backpex.Preferences.Keys.valid_value?/2`, the overlay stays empty, and the
      # dead render falls back to the stored session value.
      insert(:post, title: "Alpha", published: true)

      conn =
        conn
        |> stale_session(%{"global" => %{"sidebar_open" => true}})
        |> put_pending_writes(%{"global.sidebar_open" => "false"})
        |> get(~p"/admin/posts?filters[published][]=published")

      assert conn.status == 200
    end

    test "a cookie stamped for another identity is ignored", %{conn: conn} do
      # THE LEAK this stamp exists to close. User A closed the sidebar and hit
      # "Log out" before the POST resolved: the page went away with the promise,
      # so nothing ever retired the entry and the cookie (path=/, max-age 300,
      # shared by every tab) is still in the jar when user B logs in a minute
      # later. Unstamped, B's dead render would paint A's choice — and B's
      # `replayPending()` would POST it into B's store.
      #
      # B's session is a different session, so B's fingerprint differs, so the
      # cookie is void and B's own stored preference renders. The check runs on
      # the server: the dead render is exactly where a cookie the browser should
      # have discarded — or one any script on the origin planted — lands.
      insert(:post, title: "Alpha", published: true)

      previous_user = %{"_csrf_token" => "a-different-session-token", "backpex_preferences" => %{}}

      conn =
        conn
        |> stale_session(%{"global" => %{"sidebar_open" => true}})
        |> put_pending_writes(%{"global.sidebar_open" => false}, fingerprint(previous_user))
        |> get(~p"/admin/posts?filters[published][]=published")

      html = html_response(conn, 200)

      # The stored value wins — no trace of the previous user's write.
      assert html =~ ~s(data-sidebar-open="true")
      refute html =~ ~s(data-sidebar-open="false")
    end

    test "the fingerprint is rendered into the page for the browser to stamp with", %{conn: conn} do
      # The other half of the contract: the browser can only scope its cookie to
      # an identity the server told it about. `app_shell` renders it onto the
      # preferences hook element.
      insert(:post, title: "Alpha", published: true)

      conn =
        conn
        |> stale_session(%{})
        |> get(~p"/admin/posts?filters[published][]=published")

      html = html_response(conn, 200)
      expected = fingerprint(%{"_csrf_token" => @csrf_token, "backpex_preferences" => %{}})

      assert is_binary(expected)
      assert html =~ ~s(data-preferences-identity="#{expected}")
    end

    test "a garbage cookie does not crash the dead render", %{conn: conn} do
      # The cookie is client-written and unsigned. A truncated or third-party
      # value must degrade to "no overlay", not to a 500.
      insert(:post, title: "Alpha", published: true)

      conn =
        conn
        |> stale_session(%{"global" => %{"sidebar_open" => false}})
        |> Plug.Test.put_req_cookie(PrefLiveView.client_cookie(), "%zz-not-json")
        |> get(~p"/admin/posts?filters[published][]=published")

      html = html_response(conn, 200)

      assert html =~ ~s(data-sidebar-open="false")
    end
  end
end
