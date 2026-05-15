defmodule Backpex.Preferences.PubSubTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import Plug.Test

  alias Backpex.Preferences
  alias Backpex.Preferences.Adapter
  alias Backpex.Preferences.Adapters.Session
  alias Backpex.Preferences.Context
  alias Backpex.Preferences.Keys
  alias Backpex.Preferences.PubSubTest
  alias Backpex.Test.RejectingPreferencesAdapter
  alias Phoenix.LiveView.Socket

  @pubsub Backpex.Preferences.PubSubTest.PubSub
  @topic_prefix "backpex_preferences_test"
  @user_id "user-42"

  setup do
    start_supervised!({Phoenix.PubSub, name: @pubsub})
    :ok
  end

  # Identity resolver used by the configured-pubsub tests below.  Returns a
  # fixed user id so writes/broadcasts go to a real (non-anonymous) topic
  # — anonymous identities are intentionally a no-op for broadcast/subscribe.
  def __resolve_identity__(_ctx), do: @user_id

  describe "broadcasts are a no-op when :pubsub is not configured" do
    test "put/4 on a Conn does not broadcast" do
      # Subscribe directly via Phoenix.PubSub so we observe the *absence* of a
      # message even without the feature enabled (the module's subscribe/1
      # returns {:error, :pubsub_not_configured} in that state).
      Phoenix.PubSub.subscribe(@pubsub, @topic_prefix <> ":anonymous")

      conn = conn(:post, "/") |> Plug.Test.init_test_session(%{})
      assert {:ok, %Plug.Conn{}} = Preferences.put(conn, Keys.theme(), "dark")

      refute_receive {:backpex_preference_changed, _}, 50
    end
  end

  describe "broadcasts when :pubsub is configured" do
    setup do
      with_pubsub_config()
    end

    test "put/4 on a Conn broadcasts with source: :controller" do
      :ok = Preferences.subscribe(@user_id)

      conn = conn(:post, "/") |> Plug.Test.init_test_session(%{})
      assert {:ok, %Plug.Conn{}} = Preferences.put(conn, Keys.theme(), "dark")

      theme_key = Keys.theme()

      assert_receive {:backpex_preference_changed, %{key: ^theme_key, value: "dark", source: :controller}}
    end

    test "put/4 on a Socket (resolved :requires_http fallback) does not broadcast" do
      # A socket-origin write whose adapter refuses with :requires_http is
      # handed off to the browser as a push_event. The browser then POSTs via
      # the controller, which will broadcast with :source == :controller.
      # The socket path itself MUST NOT broadcast — the write hasn't landed.
      :ok = Preferences.subscribe(@user_id)

      socket = %Socket{
        assigns: %{__changed__: %{}},
        private: %{live_temp: %{}}
      }

      assert {:ok, %Socket{}} =
               Preferences.put(socket, Keys.theme(), "dark")

      refute_receive {:backpex_preference_changed, _}, 50
    end

    test "put/4 on a Socket with a non-session adapter broadcasts with source: :server" do
      # Swap in an adapter that accepts socket-origin writes so the dispatcher
      # takes the broadcasting branch (not the push_event fallback).
      with_adapters([{:default, Backpex.Preferences.PubSubTest.AcceptingAdapter, []}], fn ->
        :ok = Preferences.subscribe(@user_id)

        socket = %Socket{
          assigns: %{__changed__: %{}},
          private: %{live_temp: %{}}
        }

        assert {:ok, %Socket{}} =
                 Preferences.put(socket, "custom.note", "hello")

        assert_receive {:backpex_preference_changed, %{key: "custom.note", value: "hello", source: :server}}
      end)
    end

    test "put_batch/3 broadcasts per successful entry" do
      :ok = Preferences.subscribe(@user_id)

      ctx = conn(:post, "/") |> Plug.Test.init_test_session(%{}) |> Context.from_conn()
      theme_key = Keys.theme()
      sidebar_key = Keys.sidebar_open()

      entries = [
        {theme_key, "dark"},
        {sidebar_key, true}
      ]

      assert {:ok, _effects} = Preferences.put_batch(ctx, entries)

      assert_receive {:backpex_preference_changed, %{key: ^theme_key, value: "dark", source: :controller}}

      assert_receive {:backpex_preference_changed, %{key: ^sidebar_key, value: true, source: :controller}}
    end

    test "put_batch/3: entries before a failing entry broadcast; the failing entry does not" do
      # Compose: the Session adapter for `global.*`, a rejecting adapter for
      # `custom.*`. Order of entries: global.theme (OK) → custom.note (REJECT)
      # → global.sidebar_open (would succeed but is never reached).
      adapters = [
        {"global.*", Session, []},
        {"custom.*", RejectingPreferencesAdapter, []},
        {:default, Session, []}
      ]

      with_adapters(adapters, fn ->
        :ok = Preferences.subscribe(@user_id)

        ctx = conn(:post, "/") |> Plug.Test.init_test_session(%{}) |> Context.from_conn()
        theme_key = Keys.theme()
        sidebar_key = Keys.sidebar_open()

        entries = [
          {theme_key, "dark"},
          {"custom.note", "boom"},
          {sidebar_key, true}
        ]

        assert {:error, {"custom.note", :rejected}} = Preferences.put_batch(ctx, entries)

        # The successful entry did broadcast.
        assert_receive {:backpex_preference_changed, %{key: ^theme_key, value: "dark", source: :controller}}

        # The failing entry did NOT broadcast.
        refute_receive {:backpex_preference_changed, %{key: "custom.note"}}, 50

        # Entries after the failure are not dispatched at all, so no broadcast.
        refute_receive {:backpex_preference_changed, %{key: ^sidebar_key}}, 50
      end)
    end

    test "no broadcast on adapter error (put/4)" do
      with_adapters([{:default, RejectingPreferencesAdapter, []}], fn ->
        :ok = Preferences.subscribe(@user_id)

        conn = conn(:post, "/") |> Plug.Test.init_test_session(%{})

        capture_log(fn ->
          assert {:error, :rejected} = Preferences.put(conn, Keys.theme(), "dark")
        end)

        refute_receive {:backpex_preference_changed, _}, 50
      end)
    end

    test "topic encoding: :unidentified identity maps to '<prefix>:anonymous'" do
      # `topic/2` still encodes anonymous identities (used by tooling /
      # debugging output), even though subscribe/broadcast are no-ops for
      # those identities. Identified callers get their own topic.
      assert Preferences.topic(@topic_prefix, :unidentified) ==
               @topic_prefix <> ":anonymous"

      assert Preferences.topic(@topic_prefix, nil) == @topic_prefix <> ":anonymous"
      assert Preferences.topic(@topic_prefix, 42) == @topic_prefix <> ":42"
      assert Preferences.topic(@topic_prefix, "user-abc") == @topic_prefix <> ":user-abc"

      # A configured-identity write still lands on the per-identity topic.
      :ok = Preferences.subscribe(@user_id)

      conn = conn(:post, "/") |> Plug.Test.init_test_session(%{})
      assert {:ok, %Plug.Conn{}} = Preferences.put(conn, Keys.theme(), "dark")

      theme_key = Keys.theme()
      assert_receive {:backpex_preference_changed, %{key: ^theme_key, value: "dark", source: :controller}}
    end

    test "subscribe/1 and unsubscribe/1 round-trip" do
      :ok = Preferences.subscribe(@user_id)
      :ok = Preferences.unsubscribe(@user_id)

      conn = conn(:post, "/") |> Plug.Test.init_test_session(%{})
      assert {:ok, %Plug.Conn{}} = Preferences.put(conn, Keys.theme(), "dark")

      # Unsubscribed — no message should reach us.
      refute_receive {:backpex_preference_changed, _}, 50
    end

    test "a raising broadcast does not break the write and logs a warning" do
      # Point the feature at a bogus server name so Phoenix.PubSub.broadcast/3
      # raises. The write must still return {:ok, _}; a warning must be logged.
      bogus = :this_pubsub_process_does_not_exist

      Application.put_env(:backpex, Backpex.Preferences,
        adapters: Application.get_env(:backpex, Backpex.Preferences)[:adapters],
        identity: Application.get_env(:backpex, Backpex.Preferences)[:identity],
        pubsub: [server: bogus, topic_prefix: @topic_prefix]
      )

      conn = conn(:post, "/") |> Plug.Test.init_test_session(%{})

      log =
        capture_log(fn ->
          assert {:ok, %Plug.Conn{} = conn2} = Preferences.put(conn, Keys.theme(), "dark")

          # The session-level effect was still applied — the broadcast failure
          # must not have shortcut the conn update.
          assert Plug.Conn.get_session(conn2, Preferences.session_key()) ==
                   %{"global" => %{"theme" => "dark"}}
        end)

      assert log =~ "Backpex.Preferences"
      assert log =~ "broadcasting preference change"
    end
  end

  describe "subscribe/1 and unsubscribe/1 without config" do
    test "both return {:error, :pubsub_not_configured} for an identified caller" do
      # No :pubsub env — the helpers must refuse rather than silently subscribe
      # against a default server that may not exist. Anonymous identities take
      # the no-op early return and bypass this check entirely.
      assert Preferences.subscribe(@user_id) == {:error, :pubsub_not_configured}
      assert Preferences.unsubscribe(@user_id) == {:error, :pubsub_not_configured}
    end

    test "anonymous identities (nil, :unidentified) no-op even without :pubsub config" do
      # The anonymous early-return is intentionally placed before the
      # pubsub_not_configured check: callers in the on_mount handshake hit
      # subscribe/1 with nil before identity is resolved, and that path must
      # neither error nor subscribe.
      assert Preferences.subscribe(nil) == :ok
      assert Preferences.subscribe(:unidentified) == :ok
      assert Preferences.unsubscribe(nil) == :ok
      assert Preferences.unsubscribe(:unidentified) == :ok
    end
  end

  describe "anonymous identities (nil, :unidentified) are not broadcast or subscribed" do
    setup do
      with_pubsub_config()
    end

    test "subscribe(nil) does not subscribe the caller to the anonymous topic" do
      # The :pubsub feature is configured; the guard must still no-op so two
      # unidentified visitors don't share a topic.
      assert Preferences.subscribe(nil) == :ok

      Phoenix.PubSub.broadcast(
        @pubsub,
        Preferences.topic(@topic_prefix, nil),
        {:backpex_preference_changed, %{key: "global.theme", value: "dark", source: :controller}}
      )

      refute_receive {:backpex_preference_changed, _}, 50
    end

    test "subscribe(:unidentified) does not subscribe the caller to the anonymous topic" do
      assert Preferences.subscribe(:unidentified) == :ok

      Phoenix.PubSub.broadcast(
        @pubsub,
        Preferences.topic(@topic_prefix, :unidentified),
        {:backpex_preference_changed, %{key: "global.theme", value: "dark", source: :controller}}
      )

      refute_receive {:backpex_preference_changed, _}, 50
    end

    test "put/4 from a Conn does not broadcast when identity resolves to :unidentified" do
      # Default config (no :identity resolver) collapses identity to
      # :unidentified, which the broadcast helper must refuse.
      Application.put_env(:backpex, Backpex.Preferences,
        adapters: [{:default, Session, []}],
        pubsub: [server: @pubsub, topic_prefix: @topic_prefix]
      )

      # Subscribe via Phoenix.PubSub directly to the anonymous topic so we can
      # observe the *absence* of a broadcast — Preferences.subscribe/1 would
      # itself no-op for :unidentified.
      Phoenix.PubSub.subscribe(@pubsub, Preferences.topic(@topic_prefix, :unidentified))

      conn = conn(:post, "/") |> Plug.Test.init_test_session(%{})
      assert {:ok, %Plug.Conn{}} = Preferences.put(conn, Keys.theme(), "dark")

      refute_receive {:backpex_preference_changed, _}, 50
    end

    test "put/4 from a Conn does not broadcast when identity resolver returns nil" do
      # Simulate a resolver that briefly returns nil during an on_mount
      # handshake. Without the guard, every unidentified visitor would share
      # the anonymous topic.
      resolver = {PubSubTest, :__resolve_nil__, []}

      Application.put_env(:backpex, Backpex.Preferences,
        adapters: [{:default, Session, []}],
        identity: resolver,
        pubsub: [server: @pubsub, topic_prefix: @topic_prefix]
      )

      Phoenix.PubSub.subscribe(@pubsub, Preferences.topic(@topic_prefix, :unidentified))
      Phoenix.PubSub.subscribe(@pubsub, Preferences.topic(@topic_prefix, nil))

      conn = conn(:post, "/") |> Plug.Test.init_test_session(%{})
      assert {:ok, %Plug.Conn{}} = Preferences.put(conn, Keys.theme(), "dark")

      refute_receive {:backpex_preference_changed, _}, 50
    end

    test "put_batch/3 does not broadcast any entry when identity is anonymous" do
      ctx = conn(:post, "/") |> Plug.Test.init_test_session(%{}) |> Context.from_conn()

      Phoenix.PubSub.subscribe(@pubsub, Preferences.topic(@topic_prefix, :unidentified))

      theme_key = Keys.theme()
      sidebar_key = Keys.sidebar_open()

      assert {:ok, _effects} =
               Preferences.put_batch(ctx, [{theme_key, "dark"}, {sidebar_key, true}])

      refute_receive {:backpex_preference_changed, _}, 50
    end
  end

  # Resolver used by the nil-identity guard test above. Lives at module level
  # so it can be referenced via {mod, fun, args} in app env.
  def __resolve_nil__(_ctx), do: nil

  # --- helpers -----------------------------------------------------------

  defp with_pubsub_config do
    prior = Application.get_env(:backpex, Backpex.Preferences)

    Application.put_env(:backpex, Backpex.Preferences,
      adapters: [{:default, Session, []}],
      identity: {PubSubTest, :__resolve_identity__, []},
      pubsub: [server: @pubsub, topic_prefix: @topic_prefix]
    )

    on_exit(fn -> restore_env(prior) end)

    :ok
  end

  defp with_adapters(adapters, fun) do
    prior = Application.get_env(:backpex, Backpex.Preferences)

    Application.put_env(:backpex, Backpex.Preferences,
      adapters: adapters,
      identity: {PubSubTest, :__resolve_identity__, []},
      pubsub: [server: @pubsub, topic_prefix: @topic_prefix]
    )

    try do
      fun.()
    after
      restore_env(prior)
    end
  end

  defp restore_env(nil), do: Application.delete_env(:backpex, Backpex.Preferences)
  defp restore_env(value), do: Application.put_env(:backpex, Backpex.Preferences, value)

  # --- fake adapters -----------------------------------------------------

  defmodule AcceptingAdapter do
    @moduledoc false
    # Accepts all writes with `:noop` so socket-origin writes take the
    # broadcasting branch rather than the :requires_http fallback.
    @behaviour Adapter

    @impl Adapter
    def get(_ctx, _key, _opts), do: {:ok, :not_found}
    @impl Adapter
    def get_map(_ctx, _prefix, _opts), do: {:ok, %{}}
    @impl Adapter
    def put(_ctx, _key, _value, _opts), do: {:ok, [:noop]}
  end
end
