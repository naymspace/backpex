defmodule Backpex.Preferences.LiveViewTest do
  use ExUnit.Case, async: false

  alias Backpex.Preferences.Adapter
  alias Backpex.Preferences.Adapters.Session
  alias Backpex.Preferences.Context
  alias Backpex.Preferences.Key
  alias Backpex.Preferences.LiveView, as: PreferenceLiveView
  alias Phoenix.LiveView.Socket
  alias Phoenix.LiveView.Utils, as: LiveViewUtils

  doctest PreferenceLiveView

  # Route tokens are MACs over the endpoint's `secret_key_base`. A stub satisfies
  # that contract without booting a Phoenix endpoint.
  defmodule Endpoint do
    @moduledoc false
    def config(:secret_key_base), do: String.duplicate("s", 64)
    def config(_key), do: nil
  end

  # An endpoint whose secret is unusable — the "degrade to no cookie" path.
  defmodule SecretlessEndpoint do
    @moduledoc false
    def config(_key), do: nil
  end

  defmodule ScopeResolver do
    @moduledoc false
    def resolve(%Context{assigns: assigns}), do: Map.get(assigns, :preference_scope, :unscoped)
  end

  defmodule ProjectedScopeAdapter do
    @moduledoc false
    @behaviour Adapter

    @impl Adapter
    def get(_ctx, _key, _opts), do: {:ok, :not_found}

    @impl Adapter
    def get_map(_ctx, _prefix, _opts), do: {:ok, %{}}

    @impl Adapter
    def put(_ctx, _key, _value, _opts), do: {:ok, :persisted}

    @impl Adapter
    def client_namespace(%Context{scope: scope}, opts) when is_map(scope) do
      {:ok, Map.take(scope, Keyword.fetch!(opts, :scope_fields))}
    end

    def client_namespace(_ctx, _opts), do: {:error, :unscoped}
  end

  setup do
    prior = Application.get_env(:backpex, Backpex.Preferences)
    config = Keyword.put(prior || [], :scope, {ScopeResolver, :resolve, []})
    Application.put_env(:backpex, Backpex.Preferences, config)

    on_exit(fn ->
      case prior do
        nil -> Application.delete_env(:backpex, Backpex.Preferences)
        value -> Application.put_env(:backpex, Backpex.Preferences, value)
      end
    end)
  end

  # A session with a CSRF token in it. Every request after the first one carries
  # it, and route tokens use it as the stable Phoenix-session identity.
  defp session(extra \\ %{}) do
    Map.merge(%{"_csrf_token" => "csrf-token-a"}, extra)
  end

  defp connected_socket(client_prefs, mount_session, scope \\ :unscoped) do
    %Socket{
      transport_pid: self(),
      endpoint: Endpoint,
      private: %{connect_params: %{"backpex_prefs" => v2_envelope(client_prefs, mount_session, scope)}}
    }
  end

  # The disconnected ("dead") render. LiveView hands the mount the `%Plug.Conn{}`
  # of the document GET in `socket.private[:connect_info]`, which is the only
  # place the browser's `backpex_prefs` cookie can be read from.
  defp disconnected_socket(raw_cookie, endpoint \\ Endpoint) do
    conn =
      :get
      |> Plug.Test.conn("/")
      |> then(fn conn ->
        case raw_cookie do
          nil -> conn
          value -> Plug.Test.put_req_cookie(conn, "backpex_prefs", value)
        end
      end)
      |> Plug.Conn.fetch_cookies()

    %Socket{endpoint: endpoint, private: %{connect_info: conn}}
  end

  # What the JS writes: `encodeURIComponent(JSON.stringify(envelope))`, where each
  # pending write carries the adapter namespace token the server served for its
  # route. `URI.encode/2` with `char_unreserved?/1` escapes
  # everything outside the unreserved set, which is the closest Elixir equivalent,
  # and `URI.decode/1` is its inverse.
  defp encode_cookie(map) do
    map
    |> Jason.encode!()
    |> URI.encode(&URI.char_unreserved?/1)
  end

  # The cookie a browser served by `session` would have written.
  defp encode_pending(values, mount_session \\ session(), scope \\ :unscoped) do
    values
    |> v2_envelope(mount_session, scope)
    |> encode_cookie()
  end

  defp v2_envelope(values, mount_session, scope) do
    entries =
      Map.new(values, fn {key, value} ->
        {key, %{"token" => token_for(key, mount_session, scope), "value" => value}}
      end)

    %{"version" => 1, "values" => entries}
  end

  defp token_for(key, mount_session, scope) do
    manifest =
      mount_session
      |> Context.from_mount(%{preference_scope: scope})
      |> PreferenceLiveView.client_manifest(Endpoint)

    manifest["routes"]
    |> Enum.filter(&route_matches?(&1, key))
    |> Enum.max_by(& &1["rank"])
    |> Map.fetch!("token")
  end

  defp route_matches?(%{"kind" => "default"}, _key), do: true
  defp route_matches?(%{"kind" => "exact", "pattern" => pattern}, key), do: pattern == key

  defp route_matches?(%{"kind" => "wildcard", "segments" => prefix}, key) do
    segments = Key.parse(key)
    Enum.take(segments, length(prefix)) == prefix
  end

  defp configure_adapters(routes) do
    config =
      :backpex
      |> Application.get_env(Backpex.Preferences, [])
      |> Keyword.put(:adapters, routes)

    Application.put_env(:backpex, Backpex.Preferences, config)
  end

  describe "event_name/0" do
    test "returns the wire event name the JS hook listens for" do
      # Pin the wire contract — the event name must stay in sync with the JS
      # hook at assets/js/hooks/_preferences.js.
      assert PreferenceLiveView.event_name() == "backpex:set_preference"
    end
  end

  describe "client_cookie/0" do
    test "returns the cookie name the JS hook writes its unacknowledged writes to" do
      # Pin the wire contract — the name must stay in sync with `COOKIE_NAME` in
      # assets/js/hooks/_preferences.js.
      assert PreferenceLiveView.client_cookie() == "backpex_prefs"
    end
  end

  describe "mount_context/2" do
    test "carries the browser's connect-param preferences on a connected mount" do
      mount_session = session(%{"backpex_preferences" => %{}})
      socket = connected_socket(%{"global.theme" => "dark"}, mount_session)

      ctx = PreferenceLiveView.mount_context(socket, mount_session)

      assert ctx.client == %{"global.theme" => "dark"}
      assert ctx.source == :mount
    end

    test "drops connect-param keys no adapter prefix serves" do
      # The payload comes from the browser: an unknown key must not shadow a
      # read, and must not reach the adapter router.
      mount_session = session()
      socket = connected_socket(%{"global.theme" => "dark", "evil.key" => "x"}, mount_session)

      ctx = PreferenceLiveView.mount_context(socket, mount_session)

      assert ctx.client == %{"global.theme" => "dark"}
    end

    test "keeps session-backed connect-param preferences across a tenant change" do
      mount_session = session()
      source_scope = %{user_id: 7, tenant_id: 70}
      destination_scope = %{user_id: 7, tenant_id: 71}

      socket = connected_socket(%{"global.theme" => "dark"}, mount_session, source_scope)

      socket = %{socket | assigns: %{preference_scope: destination_scope}}
      resolved_ctx = PreferenceLiveView.mount_context(socket, mount_session)

      assert resolved_ctx.client == %{"global.theme" => "dark"}
      assert resolved_ctx.scope == destination_scope
    end

    test "accepts connect-param preferences stamped for the resolved tenant scope" do
      mount_session = session()
      tenant_scope = %{user_id: 7, tenant_id: 70}

      socket = connected_socket(%{"global.theme" => "dark"}, mount_session, tenant_scope)
      socket = %{socket | assigns: %{preference_scope: tenant_scope}}

      resolved_ctx = PreferenceLiveView.mount_context(socket, mount_session)

      assert resolved_ctx.client == %{"global.theme" => "dark"}
      assert resolved_ctx.scope == tenant_scope
    end

    test "validates connect-param entries against each adapter namespace independently" do
      configure_adapters([
        {"global.*", Session, []},
        {"resource.*", ProjectedScopeAdapter, scope_fields: [:user_id, :tenant_id]}
      ])

      mount_session = session()
      source_scope = %{user_id: 7, tenant_id: 70}
      destination_scope = %{user_id: 7, tenant_id: 71}

      socket =
        connected_socket(
          %{
            "global.sidebar_open" => false,
            "resource:MyApp.PostLive:columns" => %{"title" => false}
          },
          mount_session,
          source_scope
        )

      socket = %{socket | assigns: %{preference_scope: destination_scope}}
      ctx = PreferenceLiveView.mount_context(socket, mount_session)

      assert ctx.client == %{"global.sidebar_open" => false}
      assert ctx.scope == destination_scope
    end

    test "has no client preferences on a disconnected mount without connect_info" do
      # A disconnected mount reads the `backpex_prefs` cookie off the document
      # GET's conn, not the connect params. This socket carries no `:connect_info`
      # at all, so there is nothing to read and the overlay stays empty.
      ctx = PreferenceLiveView.mount_context(%Socket{private: %{}}, %{})

      assert ctx.client == %{}
    end

    test "tolerates a join that sends no preferences at all" do
      socket = %Socket{transport_pid: self(), private: %{connect_params: %{"_csrf_token" => "t"}}}

      ctx = PreferenceLiveView.mount_context(socket, %{})

      assert ctx.client == %{}
    end
  end

  describe "client_manifest/2" do
    setup do
      configure_adapters([
        {"global.*", Session, []},
        {"resource.*", ProjectedScopeAdapter, scope_fields: [:user_id, :tenant_id]}
      ])

      :ok
    end

    test "keeps session-backed tokens stable while tenant-backed tokens change" do
      current = %{user_id: 7, tenant_id: 70}
      other_tenant = %{user_id: 7, tenant_id: 71}

      assert token_for("global.sidebar_open", session(), current) ==
               token_for("global.sidebar_open", session(), other_tenant)

      refute token_for("resource:MyApp.PostLive:columns", session(), current) ==
               token_for("resource:MyApp.PostLive:columns", session(), other_tenant)
    end

    test "uses only the scope projection declared by an adapter" do
      configure_adapters([
        {"resource.*", ProjectedScopeAdapter, scope_fields: [:user_id]}
      ])

      current = %{user_id: 7, tenant_id: 70}
      other_tenant = %{user_id: 7, tenant_id: 71}

      assert token_for("resource:MyApp.PostLive:columns", session(), current) ==
               token_for("resource:MyApp.PostLive:columns", session(), other_tenant)
    end

    test "changes every adapter token when the Phoenix session changes" do
      scope = %{user_id: 7, tenant_id: 70}
      other_session = %{"_csrf_token" => "csrf-token-b"}

      refute token_for("global.sidebar_open", session(), scope) ==
               token_for("global.sidebar_open", other_session, scope)

      refute token_for("resource:MyApp.PostLive:columns", session(), scope) ==
               token_for("resource:MyApp.PostLive:columns", other_session, scope)
    end

    test "returns nil when tokens cannot be signed" do
      scope = %{preference_scope: %{user_id: 7, tenant_id: 70}}
      unscoped_session = Context.from_mount(%{}, scope)
      scoped_session = Context.from_mount(session(), scope)

      assert PreferenceLiveView.client_manifest(unscoped_session, Endpoint) == nil
      assert PreferenceLiveView.client_manifest(scoped_session, SecretlessEndpoint) == nil
      assert PreferenceLiveView.client_manifest(scoped_session, nil) == nil
      assert PreferenceLiveView.client_manifest(scoped_session, Enum) == nil
    end

    test "does not expose application scope or session identifiers" do
      scope = %{user_id: 7, tenant_id: 70}

      encoded =
        session()
        |> Context.from_mount(%{preference_scope: scope})
        |> PreferenceLiveView.client_manifest(Endpoint)
        |> Jason.encode!()

      refute encoded =~ "csrf-token-a"
      refute encoded =~ "tenant_id"
      refute encoded =~ "70"
    end
  end

  describe "mount_context/2 on a disconnected mount" do
    test "carries the browser's unacknowledged writes from the backpex_prefs cookie" do
      # The whole point of the cookie: the session cookie a document GET carries
      # can be a full POST round-trip behind the user's last write, so the dead
      # render must read the browser's pending writes to paint the right state.
      socket = disconnected_socket(encode_pending(%{"global.sidebar_open" => false}))

      ctx = PreferenceLiveView.mount_context(socket, session(%{"backpex_preferences" => %{}}))

      assert ctx.client == %{"global.sidebar_open" => false}
      assert ctx.source == :mount
    end

    test "retains only cookie entries valid for the destination adapter namespace" do
      configure_adapters([
        {"global.*", Session, []},
        {"resource.*", ProjectedScopeAdapter, scope_fields: [:user_id, :tenant_id]}
      ])

      mount_session = session()
      source_scope = %{user_id: 7, tenant_id: 70}
      destination_scope = %{user_id: 7, tenant_id: 71}

      cookie =
        encode_pending(
          %{
            "global.sidebar_open" => false,
            "resource:MyApp.PostLive:columns" => %{"title" => false}
          },
          mount_session,
          source_scope
        )

      socket = disconnected_socket(cookie)
      socket = %{socket | assigns: %{preference_scope: destination_scope}}
      ctx = PreferenceLiveView.mount_context(socket, mount_session)

      assert ctx.client == %{"global.sidebar_open" => false}
    end

    test "drops a malformed entry without dropping valid siblings" do
      scope = %{user_id: 7, tenant_id: 70}
      valid_token = token_for("global.sidebar_open", session(), scope)

      cookie =
        encode_cookie(%{
          "version" => 1,
          "values" => %{
            "global.sidebar_open" => %{"token" => valid_token, "value" => false},
            "global.theme" => %{"token" => 123, "value" => "dark"}
          }
        })

      socket = disconnected_socket(cookie)
      socket = %{socket | assigns: %{preference_scope: scope}}
      ctx = PreferenceLiveView.mount_context(socket, session())

      assert ctx.client == %{"global.sidebar_open" => false}
    end

    test "ignores session-backed cookie entries from another Phoenix session" do
      # THE LEAK. User A toggles a preference and logs out before the POST
      # resolves: nothing retires the entry, and the cookie (path=/, max-age 300)
      # survives into user B's session. Rendering it would paint A's choice for B,
      # and B's replay would POST it into B's store.
      #
      # B's renewed session produces a different route token, so A's entry is
      # void. The server performs this check on the dead render and does not
      # trust the browser to have discarded an outlived or planted cookie.
      users_session = session()
      other_session = %{"_csrf_token" => "csrf-token-b"}

      socket = disconnected_socket(encode_pending(%{"global.sidebar_open" => false}, other_session))

      ctx = PreferenceLiveView.mount_context(socket, users_session)

      assert ctx.client == %{}
    end

    test "ignores cookies without the versioned per-entry token envelope" do
      bare = encode_cookie(%{"global.sidebar_open" => false})
      unstamped = encode_cookie(%{"values" => %{"global.sidebar_open" => false}})
      unknown_version = encode_cookie(%{"version" => 0, "values" => %{"global.sidebar_open" => false}})

      for cookie <- [bare, unstamped, unknown_version] do
        socket = disconnected_socket(cookie)
        ctx = PreferenceLiveView.mount_context(socket, session())

        assert ctx.client == %{}
      end
    end

    test "ignores the cookie entirely when namespace tokens cannot be computed" do
      # No secret to key the digest with (and, equivalently, a session with no CSRF
      # token): we cannot tell which namespace owns the writes, so we behave as if
      # the cookie did not exist — a potentially stale first paint, never a leak.
      cookie = encode_pending(%{"global.sidebar_open" => false})

      secretless = disconnected_socket(cookie, SecretlessEndpoint)
      ctx = PreferenceLiveView.mount_context(secretless, session())

      assert ctx.client == %{}

      # A session with no CSRF token yet: same degrade, other input.
      socket = disconnected_socket(cookie)
      ctx = PreferenceLiveView.mount_context(socket, %{})

      assert ctx.client == %{}
    end

    test "drops cookie keys no adapter prefix serves" do
      # Same gate as the connect params: the cookie is written by the browser and
      # is not signed, so an unknown key must never shadow a read or reach the
      # adapter router. `Context.put_client/2` runs `Key.validate/1`. A namespace
      # token does not prove that a key or value is sane, so both gates run.
      socket = disconnected_socket(encode_pending(%{"global.theme" => "dark", "evil.key" => 1}))

      ctx = PreferenceLiveView.mount_context(socket, session())

      assert ctx.client == %{"global.theme" => "dark"}
    end

    test "has no client preferences when the request carries no cookie" do
      socket = disconnected_socket(nil)

      ctx = PreferenceLiveView.mount_context(socket, session())

      assert ctx.client == %{}
    end

    test "degrades to no client preferences on a malformed percent-escape" do
      # `URI.decode/1` raises `ArgumentError` on a truncated escape. A cookie the
      # client wrote (or a proxy mangled) must never crash a mount.
      socket = disconnected_socket("%zz%")

      ctx = PreferenceLiveView.mount_context(socket, session())

      assert ctx.client == %{}
    end

    test "degrades to no client preferences when the cookie is not JSON" do
      socket = disconnected_socket("not-json")

      ctx = PreferenceLiveView.mount_context(socket, session())

      assert ctx.client == %{}
    end

    test "degrades to no client preferences when the cookie holds a JSON array" do
      # Only an envelope object is a cookie Backpex wrote. An array or scalar must
      # not reach `Context.put_client/2`, which expects a map.
      socket = disconnected_socket(URI.encode(~s(["global.theme"]), &URI.char_unreserved?/1))

      ctx = PreferenceLiveView.mount_context(socket, session())

      assert ctx.client == %{}
    end

    test "degrades to no client preferences when the cookie holds a JSON scalar" do
      socket = disconnected_socket("42")

      ctx = PreferenceLiveView.mount_context(socket, session())

      assert ctx.client == %{}
    end

    test "degrades to no client preferences when the cookie exceeds the size cap" do
      # The JS caps the cookie at 3KB; anything past the 4KB read cap is not a
      # cookie Backpex wrote, so decode it we will not.
      oversized = encode_pending(%{"global.theme" => String.duplicate("a", 5_000)})

      assert byte_size(oversized) > 4_096

      socket = disconnected_socket(oversized)

      ctx = PreferenceLiveView.mount_context(socket, session())

      assert ctx.client == %{}
    end

    test "TRIPWIRE: degrades to no client preferences when connect_info is not a %Plug.Conn{}" do
      # `socket.private[:connect_info]` is a LiveView internal: on the dead render
      # `Phoenix.LiveView.Static` puts the request's `%Plug.Conn{}` there, and
      # `get_connect_info/2` has no `:cookies` clause, so there is no public way
      # to reach the cookie from `on_mount`.
      #
      # If LiveView ever changes that shape the match stops matching, the overlay
      # silently degrades to `%{}` (today's behavior) and the first-paint flash
      # comes back with no crash to tell anyone. THIS test is the tripwire: if it
      # is the only one left green while the `%Plug.Conn{}` cases above go red,
      # the internal moved.
      assert PreferenceLiveView.mount_context(%Socket{private: %{connect_info: %{}}}, %{}).client == %{}

      assert PreferenceLiveView.mount_context(%Socket{private: %{connect_info: nil}}, %{}).client == %{}

      assert PreferenceLiveView.mount_context(%Socket{private: %{}}, %{}).client == %{}
    end
  end

  describe "push_write/3" do
    test "queues a push_event with the helper's event name on the socket" do
      # Build a minimal socket compatible with Phoenix.LiveView.push_event/3 —
      # the function updates `socket.private.live_temp[:push_events]` in place.
      socket = %Socket{private: %{live_temp: %{}}}

      socket = PreferenceLiveView.push_write(socket, "global.theme", "dark")

      events = LiveViewUtils.get_push_events(socket)

      assert events == [["backpex:set_preference", %{key: "global.theme", value: "dark"}]]
    end
  end

  describe "push_write/4 with mirror: :session" do
    test "includes the mirror flag in the payload" do
      socket = %Socket{private: %{live_temp: %{}}}

      socket = PreferenceLiveView.push_write(socket, "global.theme", "dark", mirror: :session)

      events = LiveViewUtils.get_push_events(socket)

      assert events == [
               ["backpex:set_preference", %{key: "global.theme", value: "dark", mirror: "session"}]
             ]
    end
  end
end
