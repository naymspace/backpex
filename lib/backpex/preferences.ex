defmodule Backpex.Preferences do
  @moduledoc """
  Unified preference management for Backpex.

  Preferences are stored in the Phoenix session as nested maps,
  but accessed via dot-notation keys for convenience.

  ## Key Format

  Keys use dot-notation with the first segment as namespace:

  - `global.*` - Application-wide preferences (theme, sidebar)
  - `resource.<Name>.*` - Per-resource preferences (columns, metrics)
  - `custom.*` - User-defined preferences

  ## Examples

      # Reading preferences
      Preferences.get(session, "global.theme")
      #=> "dark"

      Preferences.get(session, "global.sidebar_open", default: true)
      #=> true

      Preferences.get(session, "resource.UserLive.columns")
      #=> %{"name" => true, "email" => false}

      # Writing preferences (used by controller)
      Preferences.put(%{}, "global.theme", "dark")
      #=> %{"global" => %{"theme" => "dark"}}
  """

  @session_key "backpex_preferences"

  @doc """
  Returns the session key used for storing preferences.
  """
  def session_key, do: @session_key

  @doc """
  Gets a preference value from the session using dot-notation key.

  ## Options

  - `:default` - Value to return if key not found (default: nil)
  """
  def get(session, key, opts \\ []) do
    default = Keyword.get(opts, :default)
    path = parse_key(key)

    value =
      session
      |> Map.get(@session_key, %{})
      |> get_in(path)

    if is_nil(value), do: default, else: value
  end

  @doc """
  Puts a preference value into the preferences map.

  Deep merges the value, preserving sibling keys.
  """
  def put(preferences, key, value) do
    path = parse_key(key)
    deep_put(preferences, path, value)
  end

  @doc """
  Parses a dot-notation key into path segments.
  """
  def parse_key(key) when is_binary(key) do
    String.split(key, ".")
  end

  @doc """
  Gets a nested map at the given path.

  Useful for getting all values under a prefix, like all sidebar section states.

  ## Examples

      Preferences.get_map(session, "global.sidebar_section")
      #=> %{"blog" => true, "settings" => false}
  """
  def get_map(session, key) do
    path = parse_key(key)

    result =
      session
      |> Map.get(@session_key, %{})
      |> get_in(path)

    case result do
      nil -> %{}
      map when is_map(map) -> map
      _other -> %{}
    end
  end

  defp deep_put(map, [key], value) do
    Map.put(map, key, value)
  end

  defp deep_put(map, [key | rest], value) do
    child = Map.get(map, key, %{})
    Map.put(map, key, deep_put(child, rest, value))
  end
end
