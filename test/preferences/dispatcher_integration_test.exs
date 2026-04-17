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

    key = "resource:MyApp.MyLive:columns"
    value = %{"name" => true}

    assert {:ok, _effects} = Preferences.put_batch(ctx, [{key, value}])
    assert InMemory.dump() == %{key => value}
  end

  test "reads via get/3 pull from the routed adapter" do
    ctx = %{Context.from_mount(%{}) | source: :controller}
    {:ok, _effects} = Preferences.put_batch(ctx, [{"resource:MyApp.MyLive:columns", %{"name" => true}}])

    read_ctx = Context.from_mount(%{})
    assert Preferences.get(read_ctx, "resource:MyApp.MyLive:columns") == %{"name" => true}
  end

  test "cross-adapter batch: session + in-memory compose in one call" do
    ctx = %{Context.from_mount(%{}) | source: :controller}

    entries = [
      {"global.theme", "dark"},
      {"resource:MyApp.MyLive:columns", %{"name" => true}}
    ]

    assert {:ok, effects} = Preferences.put_batch(ctx, entries)

    # Session effect is present for the global.* key
    assert Enum.any?(effects, &match?({:put_session, "backpex_preferences", _}, &1))
    # In-memory adapter persisted the resource.* key directly
    assert InMemory.dump() == %{"resource:MyApp.MyLive:columns" => %{"name" => true}}
  end
end
