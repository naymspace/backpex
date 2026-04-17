defmodule Backpex.Preferences.Key do
  @moduledoc """
  Parsing and construction helpers for preference keys.

  Preference keys are string identifiers made of path segments. Two forms are
  understood:

  - Dot-separated: `"global.theme"` — the default form for keys with no
    embedded module names.
  - Colon-separated: `"resource:MyApp.MyLive:columns"` — used when a segment
    itself contains dots (typically because it embeds a module name). Colon is
    a safe secondary separator that avoids dot-collision inside that segment.

  The colon form takes precedence: if the key contains `":"` anywhere, the
  parser splits on `":"`. Otherwise it splits on `"."`.

  ## Why two forms?

  Module names in Elixir already contain dots (`Elixir.DemoWeb.PostLive`). Using
  them inside dot-separated keys creates accidental nesting:
  `"resource.Elixir.DemoWeb.PostLive.columns"` splits into five path segments,
  making stored preferences hard to reason about. Switching the whole key to
  colons lets the module live as a single atomic segment.
  """

  @doc """
  Splits a key into path segments.

  ## Examples

      iex> Backpex.Preferences.Key.parse("global.theme")
      ["global", "theme"]

      iex> Backpex.Preferences.Key.parse("resource:MyApp.MyLive:columns")
      ["resource", "MyApp.MyLive", "columns"]

      iex> Backpex.Preferences.Key.parse("global")
      ["global"]
  """
  @spec parse(String.t()) :: [String.t()]
  def parse(key) when is_binary(key) do
    if String.contains?(key, ":") do
      String.split(key, ":")
    else
      String.split(key, ".")
    end
  end

  @doc """
  Encodes a module atom for use as a single path segment.

  Pair with the colon-separated key form so dots inside the module name do not
  create accidental nesting.

  ## Examples

      iex> Backpex.Preferences.Key.encode_module(Backpex.Preferences)
      "Backpex.Preferences"

      iex> Backpex.Preferences.Key.resource_key(Backpex.Preferences, "columns")
      "resource:Backpex.Preferences:columns"
  """
  @spec encode_module(module()) :: String.t()
  def encode_module(module) when is_atom(module) do
    inspect(module)
  end

  @doc """
  Builds a `resource:<module>:<suffix>` key.

  ## Examples

      iex> Backpex.Preferences.Key.resource_key(Backpex.Preferences, "metrics_visible")
      "resource:Backpex.Preferences:metrics_visible"
  """
  @spec resource_key(module(), String.t()) :: String.t()
  def resource_key(module, suffix) when is_atom(module) and is_binary(suffix) do
    "resource:" <> encode_module(module) <> ":" <> suffix
  end

  @doc """
  Returns true when `pattern` matches `key`.

  Patterns support a single trailing `"*"` as a wildcard over the remaining
  segments. An exact string pattern matches by equality.

  ## Examples

      iex> Backpex.Preferences.Key.match?("resource.*", "resource:MyApp.MyLive:columns")
      true

      iex> Backpex.Preferences.Key.match?("global.*", "global.theme")
      true

      iex> Backpex.Preferences.Key.match?("global.*", "resource.foo")
      false

      iex> Backpex.Preferences.Key.match?("global.theme", "global.theme")
      true
  """
  @spec match?(String.t(), String.t()) :: boolean()
  def match?(pattern, key) when is_binary(pattern) and is_binary(key) do
    case String.split(pattern, ".", parts: 2) do
      [prefix, "*"] ->
        segments = parse(key)
        match_prefix?(prefix, segments)

      _no_wildcard ->
        pattern == key
    end
  end

  defp match_prefix?(prefix, [first | _rest]), do: first == prefix
  defp match_prefix?(_prefix, []), do: false
end
