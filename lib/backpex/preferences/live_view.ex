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

  alias Phoenix.LiveView
  alias Phoenix.LiveView.Socket

  @doc """
  Name of the LiveView push_event used to signal a preference write to the
  browser-side `BackpexPreferences` hook.

  Exposed for tests that need to assert on the emitted event shape.
  """
  @spec event_name() :: String.t()
  def event_name, do: "backpex:set_preference"

  @doc """
  Pushes a preference-write event to the browser.

  The `BackpexPreferences` JS hook listens for this event and persists the
  value via the preferences controller. Used from LiveView `handle_event/3`
  and `handle_params/3` callbacks when the server-originated state change
  needs to outlive the current socket.

  Returns the updated socket so it composes in pipelines.

  ## Examples

      socket
      |> Backpex.Preferences.LiveView.push_write(Backpex.Preferences.Keys.theme(), "dark")
  """
  @spec push_write(Socket.t(), String.t(), term()) :: Socket.t()
  def push_write(%Socket{} = socket, key, value) when is_binary(key) do
    LiveView.push_event(socket, event_name(), %{key: key, value: value})
  end
end
