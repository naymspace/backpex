defmodule Backpex.Preferences.LiveViewTest do
  use ExUnit.Case, async: true

  alias Backpex.Preferences.LiveView, as: PreferenceLiveView
  alias Phoenix.LiveView.Socket
  alias Phoenix.LiveView.Utils, as: LiveViewUtils

  doctest PreferenceLiveView

  defp connected_socket(client_prefs) do
    %Socket{
      transport_pid: self(),
      private: %{connect_params: %{"backpex_prefs" => client_prefs}}
    }
  end

  describe "event_name/0" do
    test "returns the wire event name the JS hook listens for" do
      # Pin the wire contract — the event name must stay in sync with the JS
      # hook at assets/js/hooks/_preferences.js.
      assert PreferenceLiveView.event_name() == "backpex:set_preference"
    end
  end

  describe "connect_param/0" do
    test "returns the param name the JS hook sends on every join" do
      # Pin the wire contract — the name must stay in sync with `backpexParams`
      # in assets/js/hooks/_preferences.js.
      assert PreferenceLiveView.connect_param() == "backpex_prefs"
    end
  end

  describe "mount_context/2" do
    test "carries the browser's connect-param preferences on a connected mount" do
      socket = connected_socket(%{"global.theme" => "dark"})

      ctx = PreferenceLiveView.mount_context(socket, %{"backpex_preferences" => %{}})

      assert ctx.client == %{"global.theme" => "dark"}
      assert ctx.source == :mount
    end

    test "drops connect-param keys no adapter prefix serves" do
      # The payload comes from the browser: an unknown key must not shadow a
      # read, and must not reach the adapter router.
      socket = connected_socket(%{"global.theme" => "dark", "evil.key" => "x"})

      ctx = PreferenceLiveView.mount_context(socket, %{})

      assert ctx.client == %{"global.theme" => "dark"}
    end

    test "has no client preferences on a disconnected mount" do
      # The dead render just re-read the session over HTTP — it is authoritative
      # and there are no connect params to read.
      ctx = PreferenceLiveView.mount_context(%Socket{private: %{}}, %{})

      assert ctx.client == %{}
    end

    test "tolerates a join that sends no preferences at all" do
      socket = %Socket{transport_pid: self(), private: %{connect_params: %{"_csrf_token" => "t"}}}

      ctx = PreferenceLiveView.mount_context(socket, %{})

      assert ctx.client == %{}
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
