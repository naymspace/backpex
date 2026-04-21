defmodule Backpex.Preferences.Adapters.Session do
  @moduledoc """
  Session-backed `Backpex.Preferences` adapter.

  Stores all preferences as a single nested map under one Phoenix session key
  (`"backpex_preferences"`). Exact storage characteristics depend on the host
  app's `Plug.Session` backend (cookie, ETS, Redis, ...). The default cookie
  store has a ~4KB limit; prefer a database-backed adapter when you expect
  bulky per-user data.

  Reference implementation for the `Backpex.Preferences.Adapter` behavior — a
  reasonable template when writing your own adapter.

  ## Write-path limitations

  `put/4` returns `{:error, :requires_http}` for any source other than
  `:controller`. `Plug.Session` cannot write to the Phoenix session outside
  an HTTP request cycle. The dispatcher handles this by falling back to
  `push_event/3`, which round-trips the write through the browser and the
  preferences controller.
  """

  @behaviour Backpex.Preferences.Adapter

  alias Backpex.Preferences.Adapter
  alias Backpex.Preferences.Context
  alias Backpex.Preferences.Key

  @session_key "backpex_preferences"

  @doc "Returns the Phoenix session key used to store the preferences tree."
  @spec session_key() :: String.t()
  def session_key, do: @session_key

  @impl Adapter
  def get(%Context{session: session}, key, _opts) do
    path = Key.parse(key)
    value = session |> root() |> get_in(path)

    case value do
      nil -> {:ok, :not_found}
      value -> {:ok, value}
    end
  end

  @impl Adapter
  def get_map(%Context{session: session}, prefix, _opts) do
    path = Key.parse(prefix)
    value = get_in(root(session), path)

    case value do
      nil -> {:ok, %{}}
      map when is_map(map) -> {:ok, map}
      _other -> {:ok, %{}}
    end
  end

  @impl Adapter
  def put(%Context{source: :controller, session: session}, key, value, _opts) do
    path = Key.parse(key)
    updated = session |> root() |> deep_put(path, value)
    {:ok, [{:put_session, @session_key, updated}]}
  end

  def put(%Context{source: source}, _key, _value, _opts) when source in [:mount, :server] do
    {:error, :requires_http}
  end

  # The session key is expected to hold a map, but a misbehaving host app (or
  # a session rewrite by another plug) can stomp on it with a non-map. Coerce
  # any non-map value to `%{}` here so `get_in/2` upstream can't crash on a
  # binary/number/etc.
  defp root(session) when is_map(session) do
    case Map.get(session, @session_key) do
      map when is_map(map) -> map
      _other -> %{}
    end
  end

  defp root(_other), do: %{}

  defp deep_put(map, [k], value), do: Map.put(map, k, value)

  defp deep_put(map, [k | rest], value) do
    child = Map.get(map, k)
    child = if is_map(child), do: child, else: %{}
    Map.put(map, k, deep_put(child, rest, value))
  end
end
