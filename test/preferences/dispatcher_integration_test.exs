defmodule Backpex.Preferences.DispatcherIntegrationTest do
  @moduledoc """
  Exercises the public `Backpex.Preferences` dispatcher against the in-memory
  test adapter so we cover the cross-adapter routing path the Session-only
  tests cannot exercise.
  """

  use ExUnit.Case, async: false

  alias Backpex.Preferences
  alias Backpex.Preferences.Adapters.Session
  alias Backpex.Preferences.Context
  alias Backpex.Preferences.Keys
  alias Backpex.Preferences.LiveView, as: PreferenceLiveView
  alias Backpex.Test.InMemoryPreferencesAdapter, as: InMemory
  alias Phoenix.LiveView.Socket
  alias Phoenix.LiveView.Utils, as: LiveViewUtils

  setup do
    InMemory.reset()
    prior = Application.get_env(:backpex, Backpex.Preferences)

    Application.put_env(:backpex, Backpex.Preferences,
      adapters: [
        {"resource.*", InMemory, []},
        {:default, Session, []}
      ]
    )

    on_exit(fn ->
      case prior do
        nil -> Application.delete_env(:backpex, Backpex.Preferences)
        value -> Application.put_env(:backpex, Backpex.Preferences, value)
      end
    end)

    :ok
  end

  test "writes to resource.* go through the in-memory adapter, not the session" do
    ctx = %{Context.from_mount(%{}) | source: :controller}

    key = Keys.columns(MyApp.MyLive)
    value = %{"name" => true}

    # InMemory adapter persists eagerly ({:ok, :persisted}), so it contributes
    # no side effect for the caller to apply. Pin the contract.
    assert {:ok, effects} = Preferences.put_batch(ctx, [{key, value}])
    assert effects == []
    assert InMemory.dump() == %{key => value}
  end

  test "reads via get/3 pull from the routed adapter" do
    ctx = %{Context.from_mount(%{}) | source: :controller}
    columns_key = Keys.columns(MyApp.MyLive)
    {:ok, _effects} = Preferences.put_batch(ctx, [{columns_key, %{"name" => true}}])

    read_ctx = Context.from_mount(%{})
    assert Preferences.get(read_ctx, columns_key) == %{"name" => true}
  end

  test "cross-adapter batch: session + in-memory compose in one call" do
    ctx = %{Context.from_mount(%{}) | source: :controller}
    columns_key = Keys.columns(MyApp.MyLive)

    entries = [
      {Keys.theme(), "dark"},
      {columns_key, %{"name" => true}}
    ]

    assert {:ok, effects} = Preferences.put_batch(ctx, entries)

    # Session effect is present for the global.* key and carries the merged
    # payload. Bind the inner map so we can assert its content explicitly,
    # not just the effect shape.
    assert [{:put_session, "backpex_preferences", session_value}] =
             Enum.filter(effects, &match?({:put_session, "backpex_preferences", _value}, &1))

    assert session_value == %{"global" => %{"theme" => "dark"}}

    # In-memory adapter persisted the resource.* key directly
    assert InMemory.dump() == %{columns_key => %{"name" => true}}
  end

  describe "put/4 from a socket picks the transport the adapter needs" do
    # A minimal socket compatible with Phoenix.LiveView.push_event/3, which
    # accumulates into `socket.private.live_temp[:push_events]`.
    defp socket, do: %Socket{private: %{live_temp: %{}}}

    test "a server-side adapter persists in place and queues no push_event" do
      key = Keys.columns(MyApp.MyLive)
      value = %{"name" => true}

      # `mirror: :session` is what the columns call site passes, and it is
      # deliberately still passed here: the mirror only ever describes the
      # browser round-trip. An adapter that persists server-side is read fresh
      # at the next mount, so there is nothing to round-trip and nothing to
      # mirror — the browser is not involved at all.
      assert {:ok, socket} = Preferences.put(socket(), key, value, mirror: :session)

      assert LiveViewUtils.get_push_events(socket) == []
      assert InMemory.dump() == %{key => value}
    end

    test "the Session adapter cannot write outside HTTP, so the write round-trips through the browser" do
      assert {:ok, socket} = Preferences.put(socket(), Keys.theme(), "dark")

      assert LiveViewUtils.get_push_events(socket) ==
               [[PreferenceLiveView.event_name(), %{key: Keys.theme(), value: "dark"}]]
    end

    test "the Session adapter's fallback carries the mirror flag to the browser" do
      assert {:ok, socket} = Preferences.put(socket(), Keys.theme(), "dark", mirror: :session)

      assert LiveViewUtils.get_push_events(socket) ==
               [[PreferenceLiveView.event_name(), %{key: Keys.theme(), value: "dark", mirror: "session"}]]
    end
  end

  describe "get_map/3 through a non-Session adapter" do
    test "reads every stored key under the prefix from the routed adapter" do
      # End-to-end coverage for the Router.resolve/1 wiring that backs
      # Backpex.Preferences.get_map/3 — without this, only the router-only
      # tests exercise that code path.
      ctx = %{Context.from_mount(%{}) | source: :controller}

      entries = [
        {"resource.foo.columns", %{"name" => true, "email" => false}},
        {"resource.foo.order", ["name", "email"]}
      ]

      {:ok, _effects} = Preferences.put_batch(ctx, entries)

      read_ctx = Context.from_mount(%{})

      assert Preferences.get_map(read_ctx, "resource.foo") == %{
               "columns" => %{"name" => true, "email" => false},
               "order" => ["name", "email"]
             }
    end

    test "combines an exact child route with its wildcard parent's stored siblings" do
      key = "global.sidebar_section.blog"

      Application.put_env(:backpex, Backpex.Preferences,
        adapters: [
          {key, InMemory, []},
          {"global.*", Session, []}
        ]
      )

      session = %{
        "backpex_preferences" => %{
          "global" => %{
            "sidebar_section" => %{"blog" => true, "settings" => true}
          }
        }
      }

      write_ctx = %{Context.from_mount(session) | source: :controller}

      assert {:ok, []} = Preferences.put_batch(write_ctx, [{key, false}])
      assert InMemory.dump() == %{key => false}

      assert session
             |> Context.from_mount()
             |> Preferences.get_map("global.sidebar_section") == %{
               "blog" => false,
               "settings" => true
             }
    end
  end
end
