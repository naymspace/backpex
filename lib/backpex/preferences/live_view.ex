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
  Builds the `Backpex.Preferences.Context` for a LiveView mount.

  Combines the session and `socket.assigns` (what identity resolvers need)
  with the preferences the browser sent in its connect params, which take
  precedence over stored values.

  Those connect params are what makes preferences survive live navigation. A
  LiveView reads the session snapshot taken when the websocket connected, so on
  a `live_redirect` re-mount it cannot see any preference written since — it
  would render stale column/metric visibility. The browser mirrors those writes
  in `sessionStorage` and hands them back on every join, *before* mount renders,
  so the first render is already correct.

  Only valid for calls during `mount/3` (including `on_mount` hooks), where
  `Phoenix.LiveView.get_connect_params/1` is available. Disconnected mounts have
  no connect params; there the freshly-read session is authoritative anyway.
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
      %{}
    end
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
