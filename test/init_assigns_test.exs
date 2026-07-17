defmodule Backpex.InitAssignsTest do
  use ExUnit.Case, async: false

  alias Backpex.InitAssigns
  alias Backpex.Preferences.Adapter
  alias Backpex.Preferences.Context
  alias Backpex.Preferences.LiveView, as: PreferenceLiveView
  alias Phoenix.LiveView.Lifecycle
  alias Phoenix.LiveView.Socket

  # The only thing `Backpex.Preferences.LiveView.identity_fingerprint/2` asks of
  # an endpoint is `config(:secret_key_base)`, so a stub stands in for a booted
  # Phoenix endpoint.
  defmodule Endpoint do
    @moduledoc false
    def config(:secret_key_base), do: String.duplicate("s", 64)
    def config(_key), do: nil
  end

  # --- test-only adapter --------------------------------------------------

  defmodule StubAdapter do
    @moduledoc false
    # Returns fixed per-key values regardless of the context. Configure via
    # application env; the `fetch/1` and `fetch_map/1` functions look the key
    # up in a lookup map set by the test.
    @behaviour Adapter

    @table_env_key :backpex_init_assigns_test_stub_adapter

    def set(values) when is_map(values) do
      Application.put_env(:backpex, @table_env_key, values)
    end

    def clear, do: Application.delete_env(:backpex, @table_env_key)

    defp values, do: Application.get_env(:backpex, @table_env_key, %{})

    @impl Adapter
    def get(_ctx, key, _opts) do
      case Map.fetch(values(), key) do
        {:ok, value} -> {:ok, value}
        :error -> {:ok, :not_found}
      end
    end

    @impl Adapter
    def get_map(_ctx, prefix, _opts) do
      map =
        values()
        |> Enum.flat_map(fn {k, v} ->
          case maybe_strip(k, prefix <> ".") do
            nil -> []
            rest -> [{rest, v}]
          end
        end)
        |> Map.new()

      {:ok, map}
    end

    @impl Adapter
    def put(_ctx, _key, _value, _opts), do: {:ok, :persisted}

    defp maybe_strip(key, prefix) do
      case String.split(key, prefix, parts: 2) do
        ["", rest] -> rest
        _other -> nil
      end
    end
  end

  # --- setup --------------------------------------------------------------

  setup do
    on_exit(fn ->
      StubAdapter.clear()
      Application.delete_env(:backpex, Backpex.Preferences)
    end)

    :ok
  end

  # --- helpers ------------------------------------------------------------

  # Builds a socket compatible with `Phoenix.LiveView.attach_hook/4`.
  #
  # `attach_hook(..., :handle_params, ...)` refuses a socket with `router: nil`,
  # and both `attach_hook` and `assign/3` touch `socket.private` — so the
  # private map must carry a `:lifecycle` struct and a `:live_temp` map.
  defp build_socket do
    %Socket{
      endpoint: Endpoint,
      router: __MODULE__.Router,
      assigns: %{__changed__: %{}},
      private: %{
        connect_info: %{},
        lifecycle: %Lifecycle{},
        live_temp: %{}
      }
    }
  end

  # A connected socket carrying the preferences the browser mirrored in
  # sessionStorage and handed back in its join params.
  defp connected_socket(client_prefs) do
    socket = build_socket()

    %{
      socket
      | transport_pid: self(),
        private: Map.put(socket.private, :connect_params, %{"backpex_prefs" => client_prefs})
    }
  end

  # A disconnected (dead-render) socket carrying the document GET's conn in
  # `socket.private[:connect_info]` — the shape `Phoenix.LiveView.Static` builds —
  # with the browser's unacknowledged preference writes in the `backpex_prefs`
  # cookie.
  #
  # The cookie is stamped with the identity fingerprint of `stamped_for` — by
  # default the very session being mounted, i.e. the browser wrote it while
  # looking at a page rendered for this same user. Pass a different session to
  # simulate a cookie the *previous* user of this browser left behind.
  defp cookie_socket(client_prefs, session, stamped_for \\ nil) do
    socket = build_socket()
    fingerprint = fingerprint(stamped_for || session)

    conn =
      :get
      |> Plug.Test.conn("/")
      |> Plug.Test.put_req_cookie(
        "backpex_prefs",
        encode_cookie(%{"id" => fingerprint, "values" => client_prefs})
      )
      |> Plug.Conn.fetch_cookies()

    %{socket | private: Map.put(socket.private, :connect_info, conn)}
  end

  defp fingerprint(session) do
    session
    |> Context.from_mount()
    |> PreferenceLiveView.identity_fingerprint(Endpoint)
  end

  # Every request of a session but its first carries a CSRF token, and the
  # fingerprint needs it: it is what scopes the session-backed store.
  defp session(preferences) do
    %{"_csrf_token" => "csrf-token-a", "backpex_preferences" => preferences}
  end

  # Mirrors the browser's `encodeURIComponent(JSON.stringify(envelope))`.
  defp encode_cookie(map) do
    map
    |> Jason.encode!()
    |> URI.encode(&URI.char_unreserved?/1)
  end

  defp mount(session, socket \\ build_socket()) do
    {:cont, socket} = InitAssigns.on_mount(:default, %{}, session, socket)
    socket
  end

  # --- tests --------------------------------------------------------------

  describe "on_mount/4 with an empty session" do
    test "assigns the documented defaults (theme nil, sidebar open, no sections)" do
      socket = mount(%{})

      assert socket.assigns.current_theme == nil
      assert socket.assigns.sidebar_open == true
      assert socket.assigns.sidebar_section_states == %{}
    end

    test "treats a session that only has the preferences key present as empty" do
      socket = mount(%{"backpex_preferences" => %{}})

      assert socket.assigns.current_theme == nil
      assert socket.assigns.sidebar_open == true
      assert socket.assigns.sidebar_section_states == %{}
    end

    test "returns `{:cont, socket}` so subsequent hooks still run" do
      # The public contract of a LiveView `on_mount` hook is the `{:cont | :halt,
      # socket}` tuple. Pin the shape here so refactors cannot silently change
      # semantics (e.g. to `{:halt, ...}`).
      assert {:cont, %Socket{}} = InitAssigns.on_mount(:default, %{}, %{}, build_socket())
    end
  end

  describe "on_mount/4 with preference values present in the session" do
    test "mirrors the stored theme, sidebar_open, and sidebar_section_states" do
      session = %{
        "backpex_preferences" => %{
          "global" => %{
            "theme" => "dark",
            "sidebar_open" => false,
            "sidebar_section" => %{"users" => true, "blog" => false}
          }
        }
      }

      socket = mount(session)

      assert socket.assigns.current_theme == "dark"
      assert socket.assigns.sidebar_open == false
      assert socket.assigns.sidebar_section_states == %{"users" => true, "blog" => false}
    end

    test "falls back to the default when a non-boolean sidebar_open is stored" do
      # The write path refuses these, but a store can still hold one from an
      # earlier Backpex version or a third-party adapter. `app_shell/1` renders
      # `inert={not @sidebar_open}`, which raises on anything but a boolean — so
      # passing the stored value through would 500 every admin page for as long
      # as the value lived, with no way to reach a page to clear it.
      session = %{"backpex_preferences" => %{"global" => %{"sidebar_open" => "nope"}}}
      socket = mount(session)
      assert socket.assigns.sidebar_open == true
    end
  end

  describe "on_mount/4 with a malformed session" do
    test "falls back to defaults when `backpex_preferences` is a binary" do
      # Pathological but possible: a host app stomps on the session key with a
      # non-map. The Session adapter's `root/1` guards against this and the
      # on_mount hook must not crash.
      socket = mount(%{"backpex_preferences" => "oops"})

      assert socket.assigns.current_theme == nil
      assert socket.assigns.sidebar_open == true
      assert socket.assigns.sidebar_section_states == %{}
    end

    test "falls back to defaults when `backpex_preferences` is explicitly nil" do
      socket = mount(%{"backpex_preferences" => nil})

      assert socket.assigns.current_theme == nil
      assert socket.assigns.sidebar_open == true
      assert socket.assigns.sidebar_section_states == %{}
    end

    test "returns the stored value unchanged when the theme slot holds a non-string" do
      # The Session adapter doesn't type-check; surfacing the raw value lets
      # layout code decide whether to coerce. Pin current behavior so a silent
      # change to coerce-at-read surfaces here.
      session = %{"backpex_preferences" => %{"global" => %{"theme" => 42}}}
      socket = mount(session)
      assert socket.assigns.current_theme == 42
    end

    test "sidebar_section_states falls back to %{} when the stored subtree is not a map" do
      # `Preferences.get_map/3` must degrade to `%{}` rather than returning a
      # scalar for the sidebar_section sub-tree — otherwise callers that
      # pattern-match on a map in the layout crash.
      session = %{
        "backpex_preferences" => %{"global" => %{"sidebar_section" => "not-a-map"}}
      }

      socket = mount(session)
      assert socket.assigns.sidebar_section_states == %{}
    end
  end

  describe "on_mount/4 with a custom Preferences adapter" do
    test "the adapter's value for global.theme wins over anything in the session" do
      # Route every key through StubAdapter and seed a value for `global.theme`.
      # Despite the session also holding a theme, the adapter result must win —
      # this is what lets a DB-backed adapter override session state.
      Application.put_env(:backpex, Backpex.Preferences, adapters: [{:default, StubAdapter, []}])

      StubAdapter.set(%{"global.theme" => "cupcake"})

      session = %{"backpex_preferences" => %{"global" => %{"theme" => "dark"}}}
      socket = mount(session)

      assert socket.assigns.current_theme == "cupcake"
    end

    test "falls back to the :default option when the adapter reports `:not_found` for sidebar_open" do
      # StubAdapter returns `:not_found` for unknown keys. Verify the caller's
      # `default: true` option reaches the value.
      Application.put_env(:backpex, Backpex.Preferences, adapters: [{:default, StubAdapter, []}])

      StubAdapter.set(%{})

      socket = mount(%{})
      assert socket.assigns.sidebar_open == true
    end
  end

  describe "on_mount/4 hooks the current URL into :handle_params" do
    test "attaches a handle_params hook that stores the URL on :current_url" do
      # The hook itself runs on each `handle_params`. Verify both that the
      # hook is attached AND that invoking its captured function stores the
      # URL on `socket.assigns.current_url` — protects against silent regressions
      # where the hook is attached but no longer assigns the URL.
      socket = mount(%{})

      hooks = socket.private.lifecycle.handle_params
      hook = Enum.find(hooks, fn hook -> hook.id == :current_url end)
      assert hook != nil

      # `attach_hook/4` stores the user-supplied function under `:function`.
      url = "/admin/posts?filters[published][]=published"
      assert {:cont, socket_after} = hook.function.(%{}, url, socket)
      assert socket_after.assigns.current_url == url
    end
  end

  describe "on_mount/4 with preferences in the connect params" do
    test "renders the browser's mirrored values instead of the frozen session's" do
      # The live_redirect case: the session snapshot LiveView froze at connect
      # time still says the sidebar is open, but the user has closed it since
      # and the browser hands that back on the join. The connect param must win,
      # otherwise the first render is stale and visibly corrects itself.
      session = %{"backpex_preferences" => %{"global" => %{"sidebar_open" => true, "theme" => "light"}}}

      socket =
        mount(
          session,
          connected_socket(%{
            "global.sidebar_open" => false,
            "global.sidebar_section.blog" => false
          })
        )

      assert socket.assigns.sidebar_open == false
      assert socket.assigns.sidebar_section_states == %{"blog" => false}
      # Keys absent from the connect params still come from the session.
      assert socket.assigns.current_theme == "light"
    end

    test "ignores connect params on a disconnected mount" do
      # A disconnected mount has no connect params — its carrier is the cookie
      # (see below). With neither present the session is what renders.
      session = %{"backpex_preferences" => %{"global" => %{"sidebar_open" => false}}}

      socket = mount(session, build_socket())

      assert socket.assigns.sidebar_open == false
    end
  end

  describe "on_mount/4 with unacknowledged writes in the backpex_prefs cookie" do
    test "the dead render prefers the cookie overlay over a stale session" do
      # THE FLASH, at its source. The user toggled the sidebar and the theme and
      # collapsed a section, then reloaded before the preferences POST's
      # Set-Cookie landed. The session this GET carried is a full round-trip
      # behind and still says "light / open / expanded". The browser wrote its
      # unacknowledged values into `backpex_prefs` synchronously, so they ride
      # this very request and the first paint must already be correct — otherwise
      # LiveView patches it a frame later and the user sees the flip.
      #
      # This covers BOTH read paths: `get/3` (theme, sidebar_open) and
      # `get_map/3` (the sidebar_section prefix).
      session =
        session(%{
          "global" => %{
            "theme" => "light",
            "sidebar_open" => true,
            "sidebar_section" => %{"blog" => true, "users" => true}
          }
        })

      pending = %{
        "global.theme" => "dark",
        "global.sidebar_open" => false,
        "global.sidebar_section.blog" => false
      }

      socket = mount(session, cookie_socket(pending, session))

      assert socket.assigns.current_theme == "dark"
      assert socket.assigns.sidebar_open == false

      # The overlay merges into the prefix map: `blog` comes from the cookie,
      # `users` still comes from the session.
      assert socket.assigns.sidebar_section_states == %{"blog" => false, "users" => true}
    end

    test "keys absent from the cookie still render from the session" do
      # The cookie holds pending writes ONLY. It must never blank out a key the
      # server already knows about — that would make it a second store.
      session = session(%{"global" => %{"theme" => "dark", "sidebar_open" => false}})

      socket = mount(session, cookie_socket(%{"global.sidebar_open" => true}, session))

      assert socket.assigns.sidebar_open == true
      assert socket.assigns.current_theme == "dark"
    end

    test "an empty cookie leaves the session's render untouched" do
      # The steady state: nothing in flight, so the cookie is absent or empty and
      # the adapter is authoritative on every key.
      session = session(%{"global" => %{"sidebar_open" => false}})

      socket = mount(session, cookie_socket(%{}, session))

      assert socket.assigns.sidebar_open == false
    end

    test "a cookie stamped for another identity renders the session, not the cookie" do
      # User A closed the sidebar and logged out before the POST landed; the entry
      # never retired and the cookie outlived them. User B's session is a different
      # session, so the stamp does not match and the whole cookie is void: B's
      # render comes from B's stored preferences.
      previous_user = session(%{})
      session = %{"_csrf_token" => "csrf-token-b", "backpex_preferences" => %{"global" => %{"sidebar_open" => true}}}

      socket = mount(session, cookie_socket(%{"global.sidebar_open" => false}, session, previous_user))

      assert socket.assigns.sidebar_open == true
    end
  end

  describe "on_mount/4 assigns the preference identity" do
    test "assigns the fingerprint the layout stamps into the page" do
      # `app_shell` renders this into `data-preferences-identity`, where the JS
      # hook reads it to stamp (and to validate) the pending-write cookie.
      socket = mount(session(%{}))

      assert socket.assigns.preferences_identity == fingerprint(session(%{}))
      assert is_binary(socket.assigns.preferences_identity)
    end

    test "assigns nil when no fingerprint can be computed" do
      # A session with no CSRF token yet (the first request of a new session).
      # The layout then renders no attribute and the pending cookie is off — the
      # behavior from before the cookie existed.
      socket = mount(%{})

      assert socket.assigns.preferences_identity == nil
    end
  end

  # A recording adapter: every read reports the full context back to the test
  # process so we can assert on both `ctx.session` and `ctx.assigns`. This is
  # how we verify that InitAssigns builds the Context from `socket.assigns`
  # (not just the raw session) and passes it through to the dispatcher.
  defmodule RecordingAdapter do
    @moduledoc false
    @behaviour Adapter

    @impl Adapter
    def get(ctx, key, _opts) do
      send(self(), {:recorded_get, key, ctx})
      {:ok, :not_found}
    end

    @impl Adapter
    def get_map(ctx, prefix, _opts) do
      send(self(), {:recorded_get_map, prefix, ctx})
      {:ok, %{}}
    end

    @impl Adapter
    def put(_ctx, _key, _value, _opts), do: {:ok, :persisted}
  end

  describe "on_mount/4 threads socket.assigns through the Context" do
    test "every preference read receives a Context carrying the session and socket.assigns" do
      # The core DX guarantee: an Ecto-backed identity resolver should be able
      # to read `ctx.assigns.current_scope` (or whatever the host app's auth
      # hook put on the socket) rather than re-implement session-token lookup.
      Application.put_env(:backpex, Backpex.Preferences, adapters: [{:default, RecordingAdapter, []}])

      current_user = %{id: 42, email: "user@example.com"}

      socket = %{build_socket() | assigns: %{__changed__: %{}, current_user: current_user}}
      session = %{"some" => "session-data"}

      _mounted_socket = mount(session, socket)

      # Drain every recorded call and assert the Context shape.
      contexts =
        Stream.repeatedly(fn ->
          receive do
            {:recorded_get, _key, ctx} -> ctx
            {:recorded_get_map, _prefix, ctx} -> ctx
          after
            0 -> nil
          end
        end)
        |> Stream.take_while(&(&1 != nil))
        |> Enum.to_list()

      # InitAssigns reads at least three preferences: theme, sidebar_open,
      # and the sidebar_section prefix map. Every one of them must see the
      # same socket.assigns snapshot.
      assert length(contexts) >= 3

      Enum.each(contexts, fn ctx ->
        assert %Context{} = ctx
        assert ctx.session == session
        assert ctx.assigns[:current_user] == current_user
      end)
    end
  end
end
