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

  alias Backpex.Preferences.Context
  alias Phoenix.LiveView
  alias Phoenix.LiveView.Socket

  @connect_param "backpex_prefs"
  @client_cookie "backpex_prefs"
  @max_cookie_bytes 4096

  @doc """
  Name of the LiveView push_event used to signal a preference write to the
  browser-side `BackpexPreferences` hook.

  Exposed for tests that need to assert on the emitted event shape.
  """
  @spec event_name() :: String.t()
  def event_name, do: "backpex:set_preference"

  @doc """
  Name of the LiveView connect param carrying the browser's mirrored
  preferences.

  A browser contract — keep it aligned with `backpexParams` in
  `assets/js/hooks/_preferences.js`.
  """
  @spec connect_param() :: String.t()
  def connect_param, do: @connect_param

  @doc """
  Name of the cookie carrying the browser's *unacknowledged* preference writes.

  A browser contract — keep it aligned with `BackpexPreferences.cookieName()` in
  `assets/js/hooks/_preferences.js`.
  """
  @spec client_cookie() :: String.t()
  def client_cookie, do: @client_cookie

  @doc """
  Builds the `Backpex.Preferences.Context` for a LiveView mount.

  Combines the session and `socket.assigns` (what identity resolvers need)
  with the preferences the browser is holding, which take precedence over
  stored values.

  The browser overrides the server exactly when it holds a write the server has
  not acknowledged. Those writes reach us over the transport that rendered the
  page, and each transport can only see one carrier:

    * CONNECTED mount — the connect params (see `connect_param/0`). A LiveView
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
      `backpex_prefs` synchronously, so they ride the very next request and the
      first paint is already correct. Entries retire as soon as their POST
      responds, so the cookie can never shadow an adapter.

  Both carriers feed the same `Backpex.Preferences.Context` client overlay, so
  both renders derive the state from the same values and agree by construction.

  Only valid for calls during `mount/3` (including `on_mount` hooks), where
  `Phoenix.LiveView.get_connect_params/1` is available.
  """
  @spec mount_context(Socket.t(), map()) :: Context.t()
  def mount_context(%Socket{} = socket, session) when is_map(session) do
    session
    |> Context.from_mount(socket.assigns)
    |> Context.put_client(client_preferences(socket))
  end

  defp client_preferences(socket) do
    if LiveView.connected?(socket) do
      socket
      |> LiveView.get_connect_params()
      |> Kernel.||(%{})
      |> Map.get(@connect_param, %{})
    else
      disconnected_client_preferences(socket)
    end
  end

  # LiveView hands the disconnected mount the `%Plug.Conn{}` in
  # `socket.private[:connect_info]` (see `Phoenix.LiveView.Static`). There is no
  # public accessor for cookies — `get_connect_info/2` has no `:cookies` clause —
  # so match defensively and degrade to `%{}`, i.e. the behavior before the
  # cookie existed, if that internal shape ever changes.
  # `test/preferences/live_view_test.exs` is the tripwire.
  defp disconnected_client_preferences(%Socket{private: %{connect_info: %Plug.Conn{} = conn}}) do
    conn
    |> Plug.Conn.fetch_cookies()
    |> Map.fetch!(:cookies)
    |> Map.get(@client_cookie)
    |> decode_client_cookie()
  end

  defp disconnected_client_preferences(_socket), do: %{}

  # Keys are gated by `Context.put_client/2` (via `Key.validate/1`). Values are
  # not: they carry no more authority than the same value POSTed to the
  # preferences endpoint, which the client can already reach. The cookie is only
  # ever an input to a render, never to an adapter write.
  defp decode_client_cookie(raw) when is_binary(raw) and byte_size(raw) <= @max_cookie_bytes do
    with {:ok, json} <- safe_uri_decode(raw),
         {:ok, decoded} when is_map(decoded) <- Phoenix.json_library().decode(json) do
      decoded
    else
      _other -> %{}
    end
  end

  defp decode_client_cookie(_raw), do: %{}

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
  value via the preferences controller. Used from LiveView `handle_event/3`
  and `handle_params/3` callbacks when the server-originated state change
  needs to outlive the current socket.

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
  @spec push_write(Socket.t(), String.t(), term(), keyword()) :: Socket.t()
  def push_write(%Socket{} = socket, key, value, opts \\ []) when is_binary(key) do
    payload =
      case Keyword.get(opts, :mirror) do
        :session -> %{key: key, value: value, mirror: "session"}
        nil -> %{key: key, value: value}
      end

    LiveView.push_event(socket, event_name(), payload)
  end
end
