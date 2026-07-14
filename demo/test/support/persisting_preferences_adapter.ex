defmodule DemoWeb.PersistingPreferencesAdapter do
  @moduledoc """
  Server-side `Backpex.Preferences.Adapter` for tests, backed by ETS.

  Writes land immediately and report `{:ok, :persisted}`, the way a
  database-backed adapter's do. That makes it the counterpart to
  `Backpex.Preferences.Adapters.Session`, which cannot write outside an HTTP
  request cycle and has to round-trip the write through the browser: routing a
  prefix here is how `DemoWeb.Live.PreferencesPersistenceTest` asserts that a
  LiveResource write asks its adapter rather than assuming the round-trip.

  Swap it in for a prefix with:

      Application.put_env(:backpex, Backpex.Preferences,
        adapters: [
          {"resource.*", DemoWeb.PersistingPreferencesAdapter, []},
          {:default, Backpex.Preferences.Adapters.Session, []}
        ]
      )

  Call `reset/0` between tests to clear state.
  """

  @behaviour Backpex.Preferences.Adapter

  alias Backpex.Preferences.Adapter
  alias Backpex.Preferences.Key

  @table :demo_test_persisting_prefs

  @doc "Starts the backing ETS table. Safe to call multiple times."
  @spec start() :: :ok
  def start do
    case :ets.whereis(@table) do
      :undefined -> :ets.new(@table, [:named_table, :public, :set])
      _ref -> :ok
    end

    :ok
  end

  @doc "Clears the backing ETS table."
  @spec reset() :: :ok
  def reset do
    start()
    :ets.delete_all_objects(@table)
    :ok
  end

  @doc "Returns every stored entry as a flat `key => value` map."
  @spec dump() :: map()
  def dump do
    start()
    @table |> :ets.tab2list() |> Map.new()
  end

  @impl Adapter
  def get(_ctx, key, _opts) do
    start()

    case :ets.lookup(@table, key) do
      [{^key, value}] -> {:ok, value}
      [] -> {:ok, :not_found}
    end
  end

  @impl Adapter
  def get_map(_ctx, prefix, _opts) do
    start()
    prefix_segments = Key.parse(prefix)

    map =
      @table
      |> :ets.tab2list()
      |> Enum.reduce(%{}, fn {key, value}, acc ->
        case strip_prefix(Key.parse(key), prefix_segments) do
          nil -> acc
          remaining -> deep_put(acc, remaining, value)
        end
      end)

    {:ok, map}
  end

  @impl Adapter
  def put(_ctx, key, value, _opts) do
    start()
    :ets.insert(@table, {key, value})
    {:ok, :persisted}
  end

  defp strip_prefix(segments, prefix) do
    case {segments, prefix} do
      {segments, []} -> segments
      {[segment | rest_segments], [segment | rest_prefix]} -> strip_prefix(rest_segments, rest_prefix)
      _other -> nil
    end
  end

  defp deep_put(map, [key], value), do: Map.put(map, key, value)

  defp deep_put(map, [key | rest], value) do
    child = Map.get(map, key)
    child = if is_map(child), do: child, else: %{}
    Map.put(map, key, deep_put(child, rest, value))
  end
end
