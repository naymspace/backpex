defmodule Backpex.Integration.Preferences.DeadRenderTest do
  @moduledoc """
  Dead render with an unacknowledged client write.

  These are the only assertions in the suite that look at the bytes the browser paints FIRST. They use `get/2`, not
  `live/2`, so what they render is the DISCONNECTED mount — the document response to a hard reload.

  The scenario: the user toggled a preference and reloaded before the keepalive POST's `Set-Cookie` reached the cookie
  jar. The session this GET carries is one round-trip stale, so the adapter would render the PRE-toggle state and
  LiveView would patch it away a frame later. That patch is the flash. The browser's synchronously-written
  `backpex_prefs` cookie rides this request and must win.

  If the disconnected branch of `Backpex.Preferences.LiveView` ever stops working, these fail and nothing else in the
  suite does: a `live/2` test cannot see this, because its connect params already carry the overlay.
  """
  use Backpex.ConnCase, async: true

  alias Backpex.Preferences.Context
  alias Backpex.Preferences.Keys, as: PrefKeys
  alias Backpex.Preferences.LiveView, as: PrefLiveView

  @resource_mod Backpex.Test.PostLive

  # The shape `Plug.CSRFProtection` generates (18 random bytes, base64url).
  @csrf_token "0hs7B3xF1qLmNpQrStUvWx"

  test "sidebar renders closed even though the session still says open", %{conn: conn} do
    insert(:post, title: "Alpha", published: true)

    conn =
      conn
      |> stale_session(%{"global" => %{"sidebar_open" => true}})
      |> put_pending_writes(%{"global.sidebar_open" => false})
      |> get(~p"/admin/posts?filters[published][]=published")

    html = html_response(conn, 200)

    # `data-sidebar-open` drives the hook's mount-time seed, and `lg:translate-x-0` is what makes the sidebar visible on
    # desktop at first paint. Both must already reflect the user's toggle.
    assert html =~ ~s(data-sidebar-open="false")
    refute html =~ ~s(data-sidebar-open="true")
    refute html =~ "lg:translate-x-0"
  end

  test "sidebar renders open from the session when nothing is pending", %{conn: conn} do
    # The control for the case above: without a pending write the adapter is authoritative, so the cookie cannot be
    # shadowing anything.
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
    # The half of the problem no pre-paint script could ever fix: chrome can be corrected from a `<head>` script, but a
    # table that was already streamed with the wrong columns cannot. The server has to render it right.
    insert(:post, title: "Alpha", published: true)

    conn =
      conn
      |> stale_session(%{"resource" => %{inspect(@resource_mod) => %{"columns" => %{"title" => true}}}})
      |> put_pending_writes(%{PrefKeys.columns(@resource_mod) => %{"title" => false}})
      |> get(~p"/admin/posts?filters[published][]=published")

    html = html_response(conn, 200)

    # The Title column's `<th>` carries the sort link; hiding the column drops the whole cell. The toggle-columns
    # dropdown still lists `title`, so key the assertion on the order link, which only the header renders.
    refute html =~ "order_by=title"

    # Guards against a vacuous `refute`: the table's other columns still render their sort links, and `title` still
    # appears in the column-visibility dropdown (which lists every field, active or not).
    assert html =~ "order_by=likes"
    assert html =~ ~s(phx-value-field="title")
  end

  test "a visible column is present in the dead render's table", %{conn: conn} do
    insert(:post, title: "Alpha", published: true)

    conn =
      conn
      |> stale_session(%{"resource" => %{inspect(@resource_mod) => %{"columns" => %{"title" => false}}}})
      |> put_pending_writes(%{PrefKeys.columns(@resource_mod) => %{"title" => true}})
      |> get(~p"/admin/posts?filters[published][]=published")

    html = html_response(conn, 200)

    # Symmetry check: the cookie can also turn a column back ON against a session that hides it — the overlay is a real
    # overlay, not a mask.
    assert html =~ "order_by=title"
  end

  test "the root layout's data-theme reflects the pending theme write", %{conn: conn} do
    # `<html data-theme>` is rendered from `assigns[:current_theme]`, which InitAssigns reads at mount. A stale theme
    # here is the most visible flash of all: the whole page repaints.
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
    # `backpex_prefs` is non-HttpOnly (it has to be: only JS can write it synchronously), unsigned, path=/ and shared
    # across tabs, so any script on the origin can plant one. A browser-written value must therefore never decide
    # whether the page renders at all: `{"global.sidebar_open": "false"}` — a JSON *string*, not a boolean — would reach
    # `inert={not @sidebar_open}` in `Backpex.HTML.Layout.app_shell/1`, and `not "false"` raises, turning a single
    # planted cookie into an HTTP 500 on every page until it expires.
    #
    # `Context.put_client/2` drops it: the value fails `Backpex.Preferences.Keys.valid_value?/2`, the overlay stays
    # empty, and the dead render falls back to the stored session value.
    insert(:post, title: "Alpha", published: true)

    conn =
      conn
      |> stale_session(%{"global" => %{"sidebar_open" => true}})
      |> put_pending_writes(%{"global.sidebar_open" => "false"})
      |> get(~p"/admin/posts?filters[published][]=published")

    assert conn.status == 200
  end

  test "a cookie stamped for another scope is ignored", %{conn: conn} do
    # THE LEAK this stamp exists to close. User A closed the sidebar and hit "Log out" before the POST resolved: the
    # page went away with the promise, so nothing ever retired the entry and the cookie (path=/, max-age 300, shared by
    # every tab) is still in the jar when user B logs in a minute later. Unstamped, B's dead render would paint A's
    # choice — and B's `replayPending()` would POST it into B's store.
    #
    # B's session is different, so B's namespace token differs, so the entry is void and B's own stored preference
    # renders. The check runs on the server: the dead render is exactly where a cookie the browser should have
    # discarded — or one any script on the origin planted — lands.
    insert(:post, title: "Alpha", published: true)

    previous_user = %{"_csrf_token" => "a-different-session-token", "backpex_preferences" => %{}}

    conn =
      conn
      |> stale_session(%{"global" => %{"sidebar_open" => true}})
      |> put_pending_writes(%{"global.sidebar_open" => false}, previous_user)
      |> get(~p"/admin/posts?filters[published][]=published")

    html = html_response(conn, 200)

    # The stored value wins — no trace of the previous user's write.
    assert html =~ ~s(data-sidebar-open="true")
    refute html =~ ~s(data-sidebar-open="false")
  end

  test "the adapter namespace manifest is rendered for the browser", %{conn: conn} do
    # The browser can only scope an entry to a route the server told it about. `app_shell` renders the signed manifest
    # onto the preferences hook element.
    insert(:post, title: "Alpha", published: true)

    conn =
      conn
      |> stale_session(%{})
      |> get(~p"/admin/posts?filters[published][]=published")

    html = html_response(conn, 200)
    expected = namespace_token(%{"_csrf_token" => @csrf_token, "backpex_preferences" => %{}})

    assert is_binary(expected)
    assert html =~ "data-preferences-manifest="
    assert html =~ expected
  end

  test "a garbage cookie does not crash the dead render", %{conn: conn} do
    # The cookie is client-written and unsigned. A truncated or third-party value must degrade to "no overlay", not to
    # a 500.
    insert(:post, title: "Alpha", published: true)

    conn =
      conn
      |> stale_session(%{"global" => %{"sidebar_open" => false}})
      |> Plug.Test.put_req_cookie(PrefLiveView.client_cookie(), "%zz-not-json")
      |> get(~p"/admin/posts?filters[published][]=published")

    html = html_response(conn, 200)

    assert html =~ ~s(data-sidebar-open="false")
  end

  # The wire format the JS hook writes: encodeURIComponent(JSON.stringify(envelope)), where each pending write carries
  # the adapter namespace token the server rendered into `data-preferences-manifest`. By default the token belongs to the
  # session making this request.
  defp put_pending_writes(conn, writes, stamped_for \\ nil) do
    token = namespace_token(stamped_for || Plug.Conn.get_session(conn))

    entries =
      Map.new(writes, fn {key, value} ->
        {key, %{"token" => token, "value" => value}}
      end)

    encoded =
      %{"version" => 1, "values" => entries}
      |> Jason.encode!()
      |> URI.encode(&URI.char_unreserved?/1)

    Plug.Test.put_req_cookie(conn, PrefLiveView.client_cookie(), encoded)
  end

  # Every request of a session but its very first carries a CSRF token, and the route token needs it: it is what scopes
  # the session-backed preference store.
  defp stale_session(conn, preferences, csrf_token \\ @csrf_token) do
    Plug.Test.init_test_session(conn, %{
      "_csrf_token" => csrf_token,
      "backpex_preferences" => preferences
    })
  end

  defp namespace_token(session) do
    session
    |> Context.from_mount()
    |> PrefLiveView.client_manifest(Backpex.Test.Endpoint)
    |> Map.fetch!("routes")
    |> List.first()
    |> Map.fetch!("token")
  end
end
