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
  alias Backpex.Preferences.Key
  alias Backpex.Preferences.Router
  alias Phoenix.LiveView
  alias Phoenix.LiveView.Socket

  # The connect param the browser mirrors its preferences into. A wire contract
  # with `backpexParams` in `assets/js/hooks/_preferences.js`. It shares its name
  # with `@client_cookie` by coincidence, not by contract: a connect param and a
  # cookie are different namespaces, and hardening one does not rename the other.
  @connect_param "backpex_prefs"
  @client_cookie "backpex_prefs"
  @max_cookie_bytes 4096

  # Every value in the cookie envelope carries the signed namespace token of
  # the adapter route that owns its key. A wire contract with
  # `assets/js/hooks/_preferences.js`.
  @cookie_values_key "values"
  @cookie_version_key "version"
  @entry_token_key "token"
  @entry_value_key "value"

  # Domain separator, versioned. It is mixed into the digest so the same secret
  # cannot produce a colliding token for some other Backpex feature, and so a
  # future protocol change invalidates every browser-carried value in flight.
  @client_namespace_domain "backpex.preferences.client-namespace.v1"

  # 128 bits of a SHA-256 MAC. Long enough that guessing a token is
  # hopeless, short enough (22 base64url chars) not to eat the cookie budget the
  # pending writes need.
  @namespace_token_bytes 16

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
  Builds the browser routing manifest for the configured preference adapters.

  Each route carries an opaque token derived from the namespace its adapter
  actually uses. This allows session-backed values to survive a tenant change
  while values stored in a tenant-scoped adapter remain isolated. The manifest
  contains no raw session or application scope values.

  Returns `nil` when the endpoint or Phoenix session cannot provide the secrets
  required to sign the route tokens.
  """
  def client_manifest(%Context{} = ctx, endpoint) do
    with {:ok, secret} <- endpoint_secret(endpoint),
         {:ok, session_scope} <- session_scope(ctx.session) do
      ctx = Preferences.resolve_scope(ctx)

      routes =
        Router.routes()
        |> Enum.map(&manifest_route(&1, ctx, secret, session_scope))
        |> Enum.reject(&is_nil/1)

      %{"version" => 1, "routes" => routes}
    else
      :error -> nil
    end
  end

  # `endpoint.config/1` raises when the endpoint is not started (or is a bare
  # module a test built a socket with). No secret, no namespace tokens —
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
      ride the very next request. The cookie is skipped when namespace tokens
      are unavailable; in either degradation case the first paint may
      be stale until LiveView connects. Entries retire as soon as their POST
      responds, so the cookie cannot permanently shadow an adapter.

      Each cookie entry is only honored when its signed adapter namespace token
      matches the route that owns the key on this request. This is the one place
      an attacker-plantable (or simply outlived) cookie lands, so the check runs
      here and does not trust the browser to have discarded it already.

  Both carriers feed the same `Backpex.Preferences.Context` client overlay.
  When the pending value is available to both transports, the disconnected and
  connected renders derive their state from the same value.

  Only valid for calls during `mount/3` (including `on_mount` hooks), where
  `Phoenix.LiveView.get_connect_params/1` is available.
  """
  def mount_context(%Socket{} = socket, session) when is_map(session) do
    # Resolve the scope once, here: the disconnected branch needs it to
    # validate adapter namespaces, and stashing it on the Context also spares every
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
    |> decode_client_envelope(ctx, socket.endpoint)
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
    |> decode_client_cookie(ctx, socket.endpoint)
  end

  defp disconnected_client_preferences(_socket, _ctx), do: %{}

  # Three gates, in order of what they protect against:
  #
  # 1. The size cap: anything past it is not a cookie Backpex wrote (the JS caps
  #    itself at 3KB) and is not worth decoding.
  # 2. The per-entry namespace token: a value left behind by the previous user
  #    or adapter scope is dropped while compatible siblings remain available.
  #    Without a token we cannot establish the namespace, so the entry is dropped.
  # 3. Keys and values, gated downstream by `Context.put_client/2` (`Key.validate/1`
  #    and `Keys.valid_value?/2`), so a same-scope cookie still cannot put a
  #    wrong-typed value into a render.
  #
  # The token is an *additional* gate, not a replacement for (3): it proves the
  # storage namespace, not that the value is sane.
  defp decode_client_cookie(raw, ctx, endpoint) when is_binary(raw) and byte_size(raw) <= @max_cookie_bytes do
    with {:ok, json} <- safe_uri_decode(raw),
         {:ok, envelope} <- Phoenix.json_library().decode(json) do
      decode_client_envelope(envelope, ctx, endpoint)
    else
      _other -> %{}
    end
  end

  defp decode_client_cookie(_raw, _ctx, _endpoint), do: %{}

  defp decode_client_envelope(%{@cookie_version_key => 1, @cookie_values_key => values}, %Context{} = ctx, endpoint)
       when is_map(values) do
    Enum.reduce(values, %{}, fn
      {key, %{@entry_token_key => token, @entry_value_key => value}}, acc
      when is_binary(key) and is_binary(token) ->
        if valid_entry_token?(key, token, ctx, endpoint), do: Map.put(acc, key, value), else: acc

      _other, acc ->
        acc
    end)
  end

  defp decode_client_envelope(_envelope, _ctx, _endpoint), do: %{}

  defp valid_entry_token?(key, token, ctx, endpoint) do
    with :ok <- Key.validate(key),
         expected when is_binary(expected) <- client_token(key, ctx, endpoint) do
      Plug.Crypto.secure_compare(token, expected)
    else
      _other -> false
    end
  end

  defp client_token(key, ctx, endpoint) do
    with {:ok, secret} <- endpoint_secret(endpoint),
         {:ok, session_scope} <- session_scope(ctx.session),
         {adapter, opts} <- Router.resolve(key),
         {:ok, namespace} <- adapter_namespace(adapter, ctx, opts) do
      namespace_token(secret, session_scope, adapter, namespace)
    else
      _other -> nil
    end
  rescue
    ArgumentError -> nil
  end

  defp manifest_route({pattern, adapter, opts}, ctx, secret, session_scope) do
    case adapter_namespace(adapter, ctx, opts) do
      {:ok, namespace} ->
        pattern
        |> manifest_pattern()
        |> Map.put("token", namespace_token(secret, session_scope, adapter, namespace))

      _other ->
        nil
    end
  end

  defp manifest_pattern(:default), do: %{"kind" => "default", "segments" => [], "rank" => [0, 0, 0]}

  defp manifest_pattern(pattern) when is_binary(pattern) do
    case Key.wildcard_prefix(pattern) do
      nil ->
        segments = Key.parse(pattern)
        %{"kind" => "exact", "pattern" => pattern, "segments" => segments, "rank" => [1, length(segments), 1]}

      segments ->
        %{"kind" => "wildcard", "pattern" => pattern, "segments" => segments, "rank" => [1, length(segments), 0]}
    end
  end

  defp adapter_namespace(adapter, ctx, opts) do
    _module_load = Code.ensure_loaded(adapter)

    if function_exported?(adapter, :client_namespace, 2) do
      adapter.client_namespace(ctx, opts)
    else
      {:ok, {:resolved_scope, ctx.scope, opts}}
    end
  end

  defp namespace_token(secret, session_scope, adapter, namespace) do
    payload = :erlang.term_to_binary({@client_namespace_domain, adapter, namespace, session_scope})

    :hmac
    |> :crypto.mac(:sha256, secret, payload)
    |> binary_part(0, @namespace_token_bytes)
    |> Base.url_encode64(padding: false)
  end

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
