defmodule Backpex.Preferences.LiveView do
  @moduledoc """
  LiveView-side helpers for the preferences subsystem.

  Emits preference-write push_events from a LiveView and owns the wire event
  name that the `BackpexPreferences` JS hook listens for. The hook receives
  the event, POSTs to the preferences controller, and the controller
  persists through the configured adapter.

  The event name is a browser contract — treat it as a stable wire protocol
  and keep it aligned with `assets/js/hooks/_preferences.js`. The name is
  returned from `event_name/0`.
  """

  alias Backpex.Preferences
  alias Backpex.Preferences.Context
  alias Phoenix.LiveView
  alias Phoenix.LiveView.Socket

  # The connect param the browser mirrors its preferences into. A wire contract
  # with `backpexParams` in `assets/js/hooks/_preferences.js`. It shares its name
  # with `@client_cookie` by coincidence, not by contract: a connect param and a
  # cookie are different namespaces, and hardening one does not rename the other.
  @connect_param "backpex_prefs"
  @client_cookie "backpex_prefs"
  @max_cookie_bytes 4096

  # The cookie is an envelope, not a bare map: the values are only valid for the
  # scope that wrote them (see `scope_fingerprint/2`), so the fingerprint
  # travels with them. A wire contract with `assets/js/hooks/_preferences.js`.
  @cookie_scope_key "scope"
  @cookie_values_key "values"

  # Domain separator, versioned. It is mixed into the digest so the same secret
  # cannot produce a colliding fingerprint for some other Backpex feature, and so
  # a future change to what the digest covers invalidates every cookie in flight
  # instead of silently reinterpreting it.
  @fingerprint_domain "backpex.preferences.scope.v1"

  # 128 bits of a SHA-256 MAC. Long enough that guessing a fingerprint is
  # hopeless, short enough (22 base64url chars) not to eat the cookie budget the
  # pending writes need.
  @fingerprint_bytes 16

  @doc """
  Name of the LiveView push_event used to signal a preference write to the
  browser-side `BackpexPreferences` hook.

  Exposed for tests that need to assert on the emitted event shape.
  """
  def event_name, do: "backpex:set_preference"

  @doc """
  Name of the cookie carrying the browser's *unacknowledged* preference writes.

  A browser contract — keep it aligned with `COOKIE_NAME` in
  `assets/js/hooks/_preferences.js`.
  """
  def client_cookie, do: @client_cookie

  @doc """
  Opaque fingerprint of the preference scope behind this
  request, or `nil` when it cannot be computed.

  The `backpex_prefs` cookie is `path=/`, non-`HttpOnly` and lives up to five
  minutes, so a write it carries can outlive the person who made it: user A
  toggles the theme and hits "Log out" before the POST resolves (the promise dies
  with the page, so nothing ever retires the entry), user B logs in on the same
  browser a minute later, and B's dead render would be overlaid with A's value —
  and B's replay would POST it into B's store. A pending write must therefore
  only ever apply to the scope that made it, and the fingerprint is what pins
  it: the browser stamps the cookie with the value it was served, and both the
  dead render (`mount_context/2`) and the JS discard the cookie when it does not
  match the current one.

  ## What the digest covers, and why

  Two things, because a Backpex install can have more than one preference store
  and they are not scoped alike:

    * **The resolved scope** (the `:scope` MFA, see `Backpex.Preferences`).
      One resolver serves every key — the router picks the *adapter* per prefix,
      not the scope — so there is a single scope map per request. An unresolved
      scope folds into one distinct `:unscoped` value.

    * **The Phoenix session's CSRF token.** `Backpex.Preferences.Adapters.Session`
      — the default adapter, and the one behind any zero-config install — ignores
      `scope` entirely and scopes its store by the *session*. Digesting the
      scope alone would leave every unscoped session-backed install (i.e.
      the default) with one fingerprint for all users, which is the bug. The CSRF
      token is the session's stable, per-session secret: constant for the life of
      a session, unaffected by preference writes (unlike the session as a whole,
      which changes on every write), and regenerated exactly when the session is
      renewed — which is what logging in and out does (`phx.gen.auth` calls
      `delete_csrf_token/0` in its `renew_session/1`).

  Digesting both keeps the cookie's scope at least as narrow as the narrowest
  store's. An app that neither renews the session on login nor configures
  `:scope` gets the same fingerprint for A and B — but such an app also hands
  A and B *the same session*, so the Session adapter already shares the stored
  preferences between them; the cookie leaks nothing the store does not.

  The digest is a keyed MAC over the endpoint's `secret_key_base`, never the raw
  scope: any script on the origin can read this cookie, and user or tenant ids in it
  would be an identifier we do not otherwise expose.

  ## Degrading

  Returns `nil` when the endpoint has no usable `secret_key_base` or the session
  carries no CSRF token (the first request of a brand-new session, before
  `Plug.CSRFProtection` has written one back). Callers must then behave as if
  there were no cookie at all: a possibly stale first paint, never a wrong-user
  write. See `Backpex.HTML.Layout.app_shell/1`, which renders the value into
  `data-preferences-scope` for the JS hook.
  """
  def scope_fingerprint(%Context{} = ctx, endpoint) do
    with {:ok, secret} <- endpoint_secret(endpoint),
         {:ok, session_scope} <- session_scope(ctx.session) do
      scope = Preferences.resolve_scope(ctx).scope
      payload = :erlang.term_to_binary({@fingerprint_domain, scope, session_scope})

      :hmac
      |> :crypto.mac(:sha256, secret, payload)
      |> binary_part(0, @fingerprint_bytes)
      |> Base.url_encode64(padding: false)
    else
      :error -> nil
    end
  end

  # `endpoint.config/1` raises when the endpoint is not started (or is a bare
  # module a test built a socket with). No secret, no fingerprint, no cookie —
  # never a crashed mount.
  defp endpoint_secret(endpoint) when is_atom(endpoint) and not is_nil(endpoint) do
    case endpoint.config(:secret_key_base) do
      secret when is_binary(secret) and byte_size(secret) >= 20 -> {:ok, secret}
      _other -> :error
    end
  rescue
    _error -> :error
  end

  defp endpoint_secret(_endpoint), do: :error

  # `Plug.CSRFProtection` writes the token in a `before_send` callback, so it is
  # absent from the session of the very first request that generates it and
  # present on every request after. Absent means "this session has no stable
  # scope yet" — degrade rather than fold a shared placeholder into the digest,
  # which is exactly where two anonymous users would collide.
  defp session_scope(session) when is_map(session) do
    case Map.get(session, "_csrf_token") do
      token when is_binary(token) and token != "" -> {:ok, token}
      _other -> :error
    end
  end

  defp session_scope(_session), do: :error

  @doc """
  Builds the `Backpex.Preferences.Context` for a LiveView mount.

  Combines the session and `socket.assigns` (what scope resolvers need)
  with the preferences the browser is holding, which take precedence over
  stored values.

  The browser overrides the server exactly when it holds a write the server has
  not acknowledged. Those writes reach us over the transport that rendered the
  page, and each transport can only see one carrier:

    * CONNECTED mount — the `backpex_prefs` connect param. A LiveView
      reads the session snapshot taken when the websocket connected, so on a
      `live_redirect` re-mount it cannot see any preference written since and
      would render stale column/metric visibility. The browser mirrors those
      writes in `sessionStorage` and hands them back on every join, *before*
      mount renders.

    * DISCONNECTED mount — the `backpex_prefs` cookie (see `client_cookie/0`).
      The session cookie a document GET carries can be a full POST round-trip
      behind the user's last write, so the freshly-read session is *not*
      authoritative: it renders the pre-toggle state, which LiveView then
      patches away — the flash. The browser writes its unacknowledged writes to
      `backpex_prefs` synchronously, so entries that fit its 3072-byte budget
      ride the very next request. The cookie is skipped when no scope
      fingerprint is available; in either degradation case the first paint may
      be stale until LiveView connects. Entries retire as soon as their POST
      responds, so the cookie cannot permanently shadow an adapter.

      The cookie is only honored when its `scope_fingerprint/2` matches the
      scope of the request being rendered. This is the one place an
      attacker-plantable (or simply outlived) cookie lands, so the check runs
      here and does not trust the browser to have discarded it already.

  Both carriers feed the same `Backpex.Preferences.Context` client overlay.
  When the pending value is available to both transports, the disconnected and
  connected renders derive their state from the same value.

  Only valid for calls during `mount/3` (including `on_mount` hooks), where
  `Phoenix.LiveView.get_connect_params/1` is available.
  """
  def mount_context(%Socket{} = socket, session) when is_map(session) do
    # Resolve the scope once, here: the disconnected branch needs it to
    # fingerprint the cookie, and stashing it on the Context also spares every
    # `get/3` in this mount a second run of the resolver.
    ctx =
      session
      |> Context.from_mount(socket.assigns)
      |> Preferences.resolve_scope()

    Context.put_client(ctx, client_preferences(socket, ctx))
  end

  defp client_preferences(socket, ctx) do
    if LiveView.connected?(socket) do
      connected_client_preferences(socket, ctx)
    else
      disconnected_client_preferences(socket, ctx)
    end
  end

  defp connected_client_preferences(socket, ctx) do
    socket
    |> LiveView.get_connect_params()
    |> Kernel.||(%{})
    |> Map.get(@connect_param)
    |> decode_client_envelope(scope_fingerprint(ctx, socket.endpoint))
  end

  # LiveView hands the disconnected mount the `%Plug.Conn{}` in
  # `socket.private[:connect_info]` (see `Phoenix.LiveView.Static`). There is no
  # public accessor for cookies — `get_connect_info/2` has no `:cookies` clause —
  # so match defensively and degrade to `%{}`, i.e. the behavior before the
  # cookie existed, if that internal shape ever changes.
  # `test/preferences/live_view_test.exs` is the tripwire.
  defp disconnected_client_preferences(%Socket{private: %{connect_info: %Plug.Conn{} = conn}} = socket, ctx) do
    conn
    |> Plug.Conn.fetch_cookies()
    |> Map.fetch!(:cookies)
    |> Map.get(@client_cookie)
    |> decode_client_cookie(scope_fingerprint(ctx, socket.endpoint))
  end

  defp disconnected_client_preferences(_socket, _ctx), do: %{}

  # Three gates, in order of what they protect against:
  #
  # 1. The size cap: anything past it is not a cookie Backpex wrote (the JS caps
  #    itself at 3KB) and is not worth decoding.
  # 2. The fingerprint: the values belong to whoever wrote them. A cookie left
  #    behind by the previous user of this browser — or planted by any script on
  #    the origin, which a non-HttpOnly cookie invites — carries a fingerprint
  #    that cannot match this request's, and is dropped whole. No fingerprint at
  #    all (see `scope_fingerprint/2`) means we cannot tell, so we drop it too.
  # 3. Keys and values, gated downstream by `Context.put_client/2` (`Key.validate/1`
  #    and `Keys.valid_value?/2`), so a same-scope cookie still cannot put a
  #    wrong-typed value into a render.
  #
  # The fingerprint is an *additional* gate, not a replacement for (3): it proves
  # who wrote the value, not that the value is sane.
  defp decode_client_cookie(raw, fingerprint)
       when is_binary(raw) and byte_size(raw) <= @max_cookie_bytes and is_binary(fingerprint) do
    with {:ok, json} <- safe_uri_decode(raw),
         {:ok, envelope} <- Phoenix.json_library().decode(json) do
      decode_client_envelope(envelope, fingerprint)
    else
      _other -> %{}
    end
  end

  defp decode_client_cookie(_raw, _fingerprint), do: %{}

  defp decode_client_envelope(%{@cookie_scope_key => scope, @cookie_values_key => values}, fingerprint)
       when is_binary(scope) and is_binary(fingerprint) and is_map(values) do
    if Plug.Crypto.secure_compare(scope, fingerprint), do: values, else: %{}
  end

  defp decode_client_envelope(_envelope, _fingerprint), do: %{}

  # Plug does not URI-decode cookie values and the browser writes
  # `encodeURIComponent(JSON.stringify(map))`, so `URI.decode/1` is the inverse.
  # It raises on malformed percent-escapes — a client-written cookie must never
  # crash a mount.
  defp safe_uri_decode(raw) do
    {:ok, URI.decode(raw)}
  rescue
    ArgumentError -> :error
  end

  @doc """
  Pushes a preference-write event to the browser.

  The `BackpexPreferences` JS hook listens for this event and persists the
  value via the preferences controller.

  This is the *transport primitive*: it hardcodes the browser round-trip and
  never consults an adapter. Prefer `Backpex.Preferences.put/4`, which asks the
  key's adapter first and only falls back here when the adapter cannot write
  outside an HTTP request cycle (`{:error, :requires_http}` — the Session
  adapter, and the zero-config default). An adapter that persists server-side
  then costs no round-trip at all.

  Returns the updated socket so it composes in pipelines.

  ## Options

    * `:mirror` - set to `:session` to additionally mirror the value into
      the browser's sessionStorage. Required for preferences that are read
      at mount and server-rendered (for example column and metric
      visibility): the Session adapter reads the websocket-connect session
      snapshot, which is frozen for the life of the socket, so without the
      mirror any write after connect silently reverts on the next
      `live_redirect` re-mount. The browser hands mirrored values back in the
      connect params of every join, where `mount_context/2` picks them up.

  ## Examples

      socket
      |> Backpex.Preferences.LiveView.push_write(Backpex.Preferences.Keys.theme(), "dark")
  """
  def push_write(%Socket{} = socket, key, value, opts \\ []) when is_binary(key) do
    payload =
      case Keyword.get(opts, :mirror) do
        :session -> %{key: key, value: value, mirror: "session"}
        nil -> %{key: key, value: value}
      end

    LiveView.push_event(socket, event_name(), payload)
  end
end
