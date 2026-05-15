defmodule Backpex.Preferences.LiveViewTest do
  use ExUnit.Case, async: true

  alias Backpex.Preferences.LiveView, as: PreferenceLiveView
  alias Phoenix.LiveView.Utils, as: LiveViewUtils

  doctest PreferenceLiveView

  describe "event_name/0" do
    test "returns the wire event name the JS hook listens for" do
      # Pin the wire contract — the event name must stay in sync with the JS
      # hook at assets/js/hooks/_preferences.js.
      assert PreferenceLiveView.event_name() == "backpex:set_preference"
    end
  end

  describe "push_write/3" do
    test "queues a push_event with the helper's event name on the socket" do
      # Build a minimal socket compatible with Phoenix.LiveView.push_event/3 —
      # the function updates `socket.private.live_temp[:push_events]` in place.
      socket = %Phoenix.LiveView.Socket{private: %{live_temp: %{}}}

      socket = PreferenceLiveView.push_write(socket, "global.theme", "dark")

      events = LiveViewUtils.get_push_events(socket)

      assert events == [["backpex:set_preference", %{key: "global.theme", value: "dark"}]]
    end
  end
end
