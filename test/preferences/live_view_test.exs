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

  # The disconnected ("dead") render. LiveView hands the mount the `%Plug.Conn{}`
  # of the document GET in `socket.private[:connect_info]`, which is the only
  # place the browser's `backpex_prefs` cookie can be read from.
  defp disconnected_socket(raw_cookie) do
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

    %Socket{private: %{connect_info: conn}}
  end

  # What the JS writes: `encodeURIComponent(JSON.stringify(map))`. `URI.encode/2`
  # with `char_unreserved?/1` escapes everything outside the unreserved set, which
  # is the closest Elixir equivalent, and `URI.decode/1` is its inverse.
  defp encode_cookie(map) do
    map
    |> Jason.encode!()
    |> URI.encode(&URI.char_unreserved?/1)
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

  describe "client_cookie/0" do
    test "returns the cookie name the JS hook writes its unacknowledged writes to" do
      # Pin the wire contract — the name must stay in sync with
      # `BackpexPreferences.cookieName()` in assets/js/hooks/_preferences.js.
      assert PreferenceLiveView.client_cookie() == "backpex_prefs"
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

  describe "mount_context/2 on a disconnected mount" do
    test "carries the browser's unacknowledged writes from the backpex_prefs cookie" do
      # The whole point of the cookie: the session cookie a document GET carries
      # can be a full POST round-trip behind the user's last write, so the dead
      # render must read the browser's pending writes to paint the right state.
      socket = disconnected_socket(encode_cookie(%{"global.sidebar_open" => false}))

      ctx = PreferenceLiveView.mount_context(socket, %{"backpex_preferences" => %{}})

      assert ctx.client == %{"global.sidebar_open" => false}
      assert ctx.source == :mount
    end

    test "drops cookie keys no adapter prefix serves" do
      # Same gate as the connect params: the cookie is written by the browser and
      # is not signed, so an unknown key must never shadow a read or reach the
      # adapter router. `Context.put_client/2` runs `Key.validate/1`.
      socket = disconnected_socket(encode_cookie(%{"global.theme" => "dark", "evil.key" => 1}))

      ctx = PreferenceLiveView.mount_context(socket, %{})

      assert ctx.client == %{"global.theme" => "dark"}
    end

    test "has no client preferences when the request carries no cookie" do
      socket = disconnected_socket(nil)

      ctx = PreferenceLiveView.mount_context(socket, %{})

      assert ctx.client == %{}
    end

    test "degrades to no client preferences on a malformed percent-escape" do
      # `URI.decode/1` raises `ArgumentError` on a truncated escape. A cookie the
      # client wrote (or a proxy mangled) must never crash a mount.
      socket = disconnected_socket("%zz%")

      ctx = PreferenceLiveView.mount_context(socket, %{})

      assert ctx.client == %{}
    end

    test "degrades to no client preferences when the cookie is not JSON" do
      socket = disconnected_socket("not-json")

      ctx = PreferenceLiveView.mount_context(socket, %{})

      assert ctx.client == %{}
    end

    test "degrades to no client preferences when the cookie holds a JSON array" do
      # Only an object is a preference map. An array or scalar must not reach
      # `Context.put_client/2`, which expects a map.
      socket = disconnected_socket(URI.encode(~s(["global.theme"]), &URI.char_unreserved?/1))

      ctx = PreferenceLiveView.mount_context(socket, %{})

      assert ctx.client == %{}
    end

    test "degrades to no client preferences when the cookie holds a JSON scalar" do
      socket = disconnected_socket("42")

      ctx = PreferenceLiveView.mount_context(socket, %{})

      assert ctx.client == %{}
    end

    test "degrades to no client preferences when the cookie exceeds the size cap" do
      # The JS caps the cookie at 3KB; anything past the 4KB read cap is not a
      # cookie Backpex wrote, so decode it we will not.
      oversized = encode_cookie(%{"global.theme" => String.duplicate("a", 5_000)})

      assert byte_size(oversized) > 4_096

      socket = disconnected_socket(oversized)

      ctx = PreferenceLiveView.mount_context(socket, %{})

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
