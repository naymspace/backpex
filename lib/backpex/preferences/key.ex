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

  ## Separator precedence

  A single `":"` anywhere in the key flips the whole key to colon-split
  parsing. There is no "mixed" mode. Concretely:

  - `"global.theme"` — no colon → dot-split → `["global", "theme"]`
  - `"resource:Backpex.Users:columns"` — colon present → colon-split →
    `["resource", "Backpex.Users", "columns"]`
  - `"custom.bad:key"` — stray colon wins → colon-split →
    `["custom.bad", "key"]` (the `.` inside `"custom.bad"` is *not* split)

  The last example is almost certainly not what the caller intended. Prefer
  `Backpex.Preferences.Key.resource_key/2` when building keys that embed a
  module name so the colon form is applied deliberately.

  Route patterns (`Backpex.Preferences.Router`) are segmented by the same
  rule, so a pattern and the keys it is written to cover always agree on
  where the segment boundaries fall — `"resource:MyApp.MyLive:*"` covers the
  module as one segment, exactly as `resource_key/2` emits it.

  ## Edge cases

  `parse/1` is intentionally lenient: it never raises for any binary input and
  applies the separator rule uniformly. As a result, leading, trailing, or
  consecutive separators produce empty string segments (e.g. `":foo"` →
  `["", "foo"]`, `"resource:Foo:"` → `["resource", "Foo", ""]`), and the empty
  string parses to `[""]` rather than `[]`. Non-ASCII module names pass through
  unchanged because the function splits on byte-level delimiters without
  normalization. See `test/preferences/key_test.exs` for the pinned corner
  cases.

  ## Key validation

  `validate/1` checks a key's first segment against the top-level prefixes
  Backpex serves: `"global"`, `"resource"`, and `"custom"`. App-owned keys
  belong under `"custom.<your-domain>.<key>"`.

  Its job is to filter *untrusted* keys at the client trust boundary:
  `Backpex.Preferences.Context.put_client/2` drops browser-supplied keys
  that fail this check, so a planted key cannot shadow a read for a prefix
  no adapter is configured to serve. Validation is pure — it never logs and
  never raises.
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
  def encode_module(module) when is_atom(module) do
    inspect(module)
  end

  @doc """
  Builds a `resource:<module>:<suffix>` key.

  ## Examples

      iex> Backpex.Preferences.Key.resource_key(Backpex.Preferences, "metrics_visible")
      "resource:Backpex.Preferences:metrics_visible"
  """
  def resource_key(module, suffix) when is_atom(module) and is_binary(suffix) do
    "resource:" <> encode_module(module) <> ":" <> suffix
  end

  @doc """
  Returns the segments a wildcard pattern covers, or `nil` when `pattern` is
  not a wildcard.

  A wildcard is a pattern whose **final segment** is `"*"`, with at least one
  leading segment. The pattern is segmented with `parse/1` — the same rule
  keys are segmented with — so a pattern and the keys it is meant to cover
  always agree on where the segment boundaries are. This is what lets a
  colon-form pattern address a colon-form key: `"resource:MyApp.MyLive:*"`
  covers `["resource", "MyApp.MyLive"]`, keeping the module a single segment
  instead of splitting it on its dots.

  ## Examples

      iex> Backpex.Preferences.Key.wildcard_prefix("global.*")
      ["global"]

      iex> Backpex.Preferences.Key.wildcard_prefix("resource:MyApp.MyLive:*")
      ["resource", "MyApp.MyLive"]

      iex> Backpex.Preferences.Key.wildcard_prefix("global.theme")
      nil

      iex> Backpex.Preferences.Key.wildcard_prefix("*")
      nil
  """
  def wildcard_prefix(pattern) when is_binary(pattern) do
    case parse(pattern) do
      segments when length(segments) > 1 ->
        if List.last(segments) == "*", do: Enum.drop(segments, -1)

      _single_segment ->
        nil
    end
  end

  @doc """
  Returns true when `pattern` matches `key`.

  A pattern is either an exact key, which matches by string equality, or a
  wildcard ending in `"*"` (see `wildcard_prefix/1`), which matches every key
  whose leading segments are the wildcard's segments — including the key that
  is the prefix itself.

  Both sides are segmented with `parse/1`, so the wildcard's separator does
  not have to match the key's: `"resource.*"` and `"resource:*"` cover the
  same keys.

  ## Examples

      iex> Backpex.Preferences.Key.match?("resource.*", "resource:MyApp.MyLive:columns")
      true

      iex> Backpex.Preferences.Key.match?("resource:MyApp.MyLive:*", "resource:MyApp.MyLive:columns")
      true

      iex> Backpex.Preferences.Key.match?("resource:MyApp.MyLive:*", "resource:MyApp.OtherLive:columns")
      false

      iex> Backpex.Preferences.Key.match?("global.*", "global.theme")
      true

      iex> Backpex.Preferences.Key.match?("global.*", "resource.foo")
      false

      iex> Backpex.Preferences.Key.match?("global.theme", "global.theme")
      true
  """
  def match?(pattern, key) when is_binary(pattern) and is_binary(key) do
    case wildcard_prefix(pattern) do
      nil -> pattern == key
      prefix_segments -> match_prefix?(prefix_segments, parse(key))
    end
  end

  defp match_prefix?(prefix_segments, key_segments) do
    length(key_segments) >= length(prefix_segments) and
      Enum.take(key_segments, length(prefix_segments)) == prefix_segments
  end

  @builtin_prefixes ["global", "resource", "custom"]

  @doc """
  Validates a preference key.

  Returns `:ok` when the key is non-empty, parseable, and its first segment
  is one of the built-in prefixes (`"global"`, `"resource"`, `"custom"`).
  Otherwise returns one of:

    * `{:error, :empty}` — the key is `""`.
    * `{:error, :malformed}` — the key parses to nothing usable (e.g. the
      first segment is empty, like `":foo"` or `".foo"`).
    * `{:error, :unknown_prefix}` — the first segment is not built-in.

  Only the first segment is checked: this is a routing/trust check, not a
  spell-checker for the segments after it.

  Pure: never logs, never raises. Used by
  `Backpex.Preferences.Context.put_client/2` to drop browser-supplied keys
  before they reach a read.

  ## Examples

      iex> Backpex.Preferences.Key.validate("global.theme")
      :ok

      iex> Backpex.Preferences.Key.validate("resource:MyApp.UserLive:columns")
      :ok

      iex> Backpex.Preferences.Key.validate("custom.dashboard.view_mode")
      :ok

      iex> Backpex.Preferences.Key.validate("globl.theme")
      {:error, :unknown_prefix}

      iex> Backpex.Preferences.Key.validate("")
      {:error, :empty}
  """
  def validate(""), do: {:error, :empty}

  def validate(key) when is_binary(key) do
    case parse(key) do
      [""] -> {:error, :empty}
      ["" | _rest] -> {:error, :malformed}
      [first | _rest] -> check_prefix(first)
      [] -> {:error, :empty}
    end
  end

  defp check_prefix(prefix) when prefix in @builtin_prefixes, do: :ok
  defp check_prefix(_prefix), do: {:error, :unknown_prefix}
end
