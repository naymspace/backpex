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
  alias Backpex.Test.InMemoryPreferencesAdapter, as: InMemory

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

    assert {:ok, _effects} = Preferences.put_batch(ctx, [{key, value}])
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

    # Session effect is present for the global.* key
    assert Enum.any?(effects, &match?({:put_session, "backpex_preferences", _}, &1))
    # In-memory adapter persisted the resource.* key directly
    assert InMemory.dump() == %{columns_key => %{"name" => true}}
  end

  describe "get_map/3 through a non-Session adapter" do
    test "reads every stored key under the prefix from the routed adapter" do
      # End-to-end coverage for the Router.resolve_prefix/1 wiring that backs
      # Backpex.Preferences.get_map/3 — without this, only the router-only
      # tests exercise that code path.
      ctx = %{Context.from_mount(%{}) | source: :controller}

      entries = [
        {"resource.foo.columns", %{"name" => true, "email" => false}},
        {"resource.foo.order", ["name", "email"]}
      ]

      assert {:ok, _effects} = Preferences.put_batch(ctx, entries)

      read_ctx = Context.from_mount(%{})

      assert Preferences.get_map(read_ctx, "resource.foo") == %{
               "columns" => %{"name" => true, "email" => false},
               "order" => ["name", "email"]
             }
    end
  end
end
