defmodule Backpex.Preferences.LiveViewTest do
  use ExUnit.Case, async: true

  alias Backpex.Preferences.LiveView, as: PreferenceLiveView
  alias Phoenix.LiveView.Socket
  alias Phoenix.LiveView.Utils, as: LiveViewUtils

  doctest PreferenceLiveView

  describe "event_name/0" do
    test "returns the wire event name the JS hook listens for" do
      # Pin the wire contract — the event name must stay in sync with the JS
      # hook at assets/js/hooks/_preferences.js.
      assert PreferenceLiveView.event_name() == "backpex:set_preference"
    end
  end

  describe "sync_event_name/0" do
    test "returns the wire event name the JS hook pushes on mount" do
      # Pin the wire contract — the event name must stay in sync with the JS
      # hook at assets/js/hooks/_preferences.js and the handle_event hook
      # attached in Backpex.InitAssigns.
      assert PreferenceLiveView.sync_event_name() == "backpex:sync_preferences"
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
