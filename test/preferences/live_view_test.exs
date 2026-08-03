defmodule Backpex.Preferences.LiveViewTest do
  use ExUnit.Case, async: false

  alias Backpex.Preferences.Context
  alias Backpex.Preferences.LiveView, as: PreferenceLiveView
  alias Phoenix.LiveView.Socket
  alias Phoenix.LiveView.Utils, as: LiveViewUtils

  doctest PreferenceLiveView

  # The fingerprint is a MAC over the endpoint's `secret_key_base`, and
  # `scope_fingerprint/2` reaches it through `endpoint.config/1`. That is the
  # entire contract, so a stub satisfies it without booting a Phoenix endpoint.
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

  # A session with a CSRF token in it. Every request after the first one of a
  # session carries it, and the fingerprint needs it: it is what scopes the
  # session-backed store (see `scope_fingerprint/2`).
  defp session(extra \\ %{}) do
    Map.merge(%{"_csrf_token" => "csrf-token-a"}, extra)
  end

  defp connected_socket(client_prefs, mount_session, scope \\ :unscoped) do
    %Socket{
      transport_pid: self(),
      endpoint: Endpoint,
      private: %{
        connect_params: %{
          "backpex_prefs" => %{
            "scope" => fingerprint(mount_session, Endpoint, scope),
            "values" => client_prefs
          }
        }
      }
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

  # What the JS writes: `encodeURIComponent(JSON.stringify(envelope))`, where the
  # envelope stamps the pending writes with the scope fingerprint the server
  # served this page with. `URI.encode/2` with `char_unreserved?/1` escapes
  # everything outside the unreserved set, which is the closest Elixir equivalent,
  # and `URI.decode/1` is its inverse.
  defp encode_cookie(map) do
    map
    |> Jason.encode!()
    |> URI.encode(&URI.char_unreserved?/1)
  end

  # The cookie a browser served by `session` would have written.
  defp encode_pending(values, session \\ session()) do
    encode_cookie(%{"scope" => fingerprint(session), "values" => values})
  end

  defp fingerprint(session, endpoint \\ Endpoint, scope \\ :unscoped) do
    session
    |> Context.from_mount()
    |> Context.put_scope(scope)
    |> PreferenceLiveView.scope_fingerprint(endpoint)
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

    test "drops connect-param preferences stamped for another tenant scope" do
      mount_session = session()
      source_scope = %{user_id: 7, tenant_id: 70}
      destination_scope = %{user_id: 7, tenant_id: 71}

      socket = connected_socket(%{"global.theme" => "dark"}, mount_session, source_scope)

      socket = %{socket | assigns: %{preference_scope: destination_scope}}
      resolved_ctx = PreferenceLiveView.mount_context(socket, mount_session)

      assert resolved_ctx.client == %{}
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

  describe "scope_fingerprint/2" do
    test "is stable for the same scope and session" do
      assert fingerprint(session()) == fingerprint(session())
      assert is_binary(fingerprint(session()))
    end

    test "changes when the tenant part of the resolved scope changes" do
      user_scope = %{user_id: 7, tenant_id: 70}
      other_tenant_scope = %{user_id: 7, tenant_id: 71}

      refute fingerprint(session(), Endpoint, user_scope) ==
               fingerprint(session(), Endpoint, other_tenant_scope)
    end

    test "changes when the session's CSRF token changes" do
      # The session-scope half of the digest. `Backpex.Preferences.Adapters.Session`
      # scopes its store by the session and ignores scope entirely, so a renewed
      # session — which is what logging in and out does — MUST invalidate the cookie
      # even when every request is unscoped.
      refute fingerprint(session()) == fingerprint(%{"_csrf_token" => "csrf-token-b"})
    end

    test "leaks no part of the inputs" do
      # The cookie is readable by any script on the origin. The digest is keyed and
      # must not carry the scope or the session's CSRF token in the clear.
      fp = fingerprint(session(), Endpoint, %{user_id: 7, tenant_id: 70})

      refute fp =~ "csrf-token-a"
      refute fp =~ "tenant_id"
    end

    test "is nil when the session carries no CSRF token" do
      # The first request of a brand-new session: `Plug.CSRFProtection` only writes
      # the token back in a `before_send` callback, so there is no session scope to
      # digest yet. Folding a shared placeholder in instead is exactly where two
      # anonymous users would collide — degrade instead.
      assert fingerprint(%{}) == nil
    end

    test "is nil when the endpoint has no usable secret" do
      assert fingerprint(session(), SecretlessEndpoint) == nil
      assert fingerprint(session(), nil) == nil
      # A module that does not even export config/1 (a socket built in a test).
      assert fingerprint(session(), Enum) == nil
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

    test "ignores a cookie stamped with another scope" do
      # THE LEAK. User A toggles a preference and logs out before the POST
      # resolves: nothing retires the entry, and the cookie (path=/, max-age 300)
      # survives into user B's session. Rendering it would paint A's choice for B,
      # and B's replay would POST it into B's store.
      #
      # B's session is a different session, so B's fingerprint differs, so the
      # whole cookie is void — values and all. Note that the check runs HERE and
      # not only in the browser: the dead render is where an outlived or planted
      # cookie lands, and we do not trust the client to have discarded it.
      users_session = session()
      other_session = %{"_csrf_token" => "csrf-token-b"}

      socket = disconnected_socket(encode_pending(%{"global.sidebar_open" => false}, other_session))

      ctx = PreferenceLiveView.mount_context(socket, users_session)

      assert ctx.client == %{}
    end

    test "ignores a cookie whose fingerprint is missing or not a string" do
      # A pre-fingerprint cookie (a bare `{key: value}` map), or a hand-planted one
      # that omits the stamp. No stamp, no proof of who wrote it: void.
      bare = encode_cookie(%{"global.sidebar_open" => false})
      unstamped = encode_cookie(%{"values" => %{"global.sidebar_open" => false}})
      mistyped = encode_cookie(%{"scope" => 1, "values" => %{"global.sidebar_open" => false}})

      for cookie <- [bare, unstamped, mistyped] do
        socket = disconnected_socket(cookie)
        ctx = PreferenceLiveView.mount_context(socket, session())

        assert ctx.client == %{}
      end
    end

    test "ignores the cookie entirely when no fingerprint can be computed" do
      # No secret to key the digest with (and, equivalently, a session with no CSRF
      # token): we cannot tell whose writes these are, so we behave as if the cookie
      # did not exist — the pre-fingerprint first paint, never a wrong-user write.
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
      # adapter router. `Context.put_client/2` runs `Key.validate/1`. The
      # fingerprint proves who wrote the values, not that they are sane, so both
      # gates run.
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
