defmodule Backpex.Test.InMemoryPreferencesAdapter do
  @moduledoc """
  ETS-backed `Backpex.Preferences.Adapter` for tests.

  Keys and values are namespaced by the resolved scope (falling back to
  `:unscoped` when no scope is configured). Swap in during a test by
  setting:

      Application.put_env(:backpex, Backpex.Preferences,
        adapters: [{"resource.*", Backpex.Test.InMemoryPreferencesAdapter, []}]
      )

  Start the adapter once per test run (e.g. in `test_helper.exs`) via
  `start/0`, then call `reset/0` between tests to clear state.
  """

  @behaviour Backpex.Preferences.Adapter

  alias Backpex.Preferences.Adapter
  alias Backpex.Preferences.Context
  alias Backpex.Preferences.Key

  @table :backpex_test_in_memory_prefs

  @doc "Starts the backing ETS table. Safe to call multiple times."
  def start do
    case :ets.whereis(@table) do
      :undefined -> :ets.new(@table, [:named_table, :public, :set])
      _ref -> :ok
    end

    :ok
  end

  @doc "Clears the backing ETS table."
  def reset do
    start()
    :ets.delete_all_objects(@table)
    :ok
  end

  @doc "Returns the full map of stored entries for a scope."
  def dump(scope \\ :unscoped) do
    start()
    :ets.match_object(@table, {{scope, :_}, :_}) |> Map.new(fn {{_scope, k}, v} -> {k, v} end)
  end

  @impl Adapter
  def get(ctx, key, _opts) do
    start()
    scope = scope(ctx)

    case :ets.lookup(@table, {scope, key}) do
      [{_row_key, value}] -> {:ok, value}
      [] -> {:ok, :not_found}
    end
  end

  @impl Adapter
  def get_map(ctx, prefix, _opts) do
    start()
    scope = scope(ctx)
    prefix_segments = Key.parse(prefix)

    map =
      @table
      |> :ets.tab2list()
      |> Enum.reduce(%{}, fn
        {{^scope, key}, value}, acc ->
          segments = Key.parse(key)

          case strip_prefix(segments, prefix_segments) do
            nil -> acc
            remaining -> deep_put(acc, remaining, value)
          end

        _entry, acc ->
          acc
      end)

    {:ok, map}
  end

  @impl Adapter
  def put(ctx, key, value, _opts) do
    start()
    scope = scope(ctx)
    :ets.insert(@table, {{scope, key}, value})
    {:ok, :persisted}
  end

  defp scope(%Context{scope: nil}), do: :unscoped
  defp scope(%Context{scope: scope}), do: scope

  defp strip_prefix(segments, prefix) do
    case {segments, prefix} do
      {segments, []} -> segments
      {[s | rest_s], [s | rest_p]} -> strip_prefix(rest_s, rest_p)
      _other -> nil
    end
  end

  defp deep_put(map, [k], value), do: Map.put(map, k, value)

  defp deep_put(map, [k | rest], value) do
    child = Map.get(map, k)
    child = if is_map(child), do: child, else: %{}
    Map.put(map, k, deep_put(child, rest, value))
  end
end
