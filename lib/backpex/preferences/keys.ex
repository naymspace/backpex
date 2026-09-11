defmodule Backpex.Preferences.Keys do
  @moduledoc """
  Names for every Backpex-managed preference key.

  Every built-in preference (theme, sidebar state, per-resource column
  visibility, ...) is produced by a function in this module rather than an
  inline string literal, so emitters and tests share a single source for
  the name.

  ## Global keys

  Single-value keys live under the `"global."` prefix and route to the
  Session adapter by default.

    * `theme/0` — `"global.theme"`
    * `sidebar_open/0` — `"global.sidebar_open"`
    * `sidebar_section_prefix/0` — `"global.sidebar_section"` (a prefix used
      with `Backpex.Preferences.get_map/3`; individual section states are
      written from JS as `"global.sidebar_section.<id>"`).

  ## Per-resource keys

  Per-resource preferences embed the LiveResource module name as a single
  path segment using the colon-separated key form
  (`resource:<Module>:<suffix>`). Module names contain dots, so the colon
  form keeps the module as one segment rather than splitting into several
  nested ones.

    * `columns/1` — `"resource:<Module>:columns"`
    * `order/1` — `"resource:<Module>:order"`
    * `filters/1` — `"resource:<Module>:filters"`
    * `metrics_visible/1` — `"resource:<Module>:metrics_visible"`

  Key construction is delegated to `Backpex.Preferences.Key.resource_key/2`
  so the encoding stays consistent with other callers of the key helpers.
  """

  alias Backpex.Preferences.Key

  # Segments Backpex owns a reader for. Used by `shape/2` to reject writes that
  # would retype one of them from above or below.
  @global_segments ["theme", "sidebar_open", "sidebar_section"]
  @resource_segments ["columns", "metrics_visible", "order", "filters"]

  @doc """
  Key for the global UI theme.

  ## Examples

      iex> Backpex.Preferences.Keys.theme()
      "global.theme"
  """
  def theme, do: "global.theme"

  @doc """
  Key for the global sidebar open/closed state.

  ## Examples

      iex> Backpex.Preferences.Keys.sidebar_open()
      "global.sidebar_open"
  """
  def sidebar_open, do: "global.sidebar_open"

  @doc """
  Prefix for per-section sidebar open/closed state.

  The prefix is used with `Backpex.Preferences.get_map/3` to read every
  section's state in one call. Individual section writes go through the JS
  `BackpexPreferences.set(...)` helper as `"global.sidebar_section.<id>"`.

  ## Examples

      iex> Backpex.Preferences.Keys.sidebar_section_prefix()
      "global.sidebar_section"
  """
  def sidebar_section_prefix, do: "global.sidebar_section"

  @doc """
  Key for a resource's persisted column visibility.

  ## Examples

      iex> Backpex.Preferences.Keys.columns(Backpex.Preferences)
      "resource:Backpex.Preferences:columns"
  """
  def columns(live_resource) when is_atom(live_resource) do
    Key.resource_key(live_resource, "columns")
  end

  @doc """
  Key for a resource's persisted sort order.

  ## Examples

      iex> Backpex.Preferences.Keys.order(Backpex.Preferences)
      "resource:Backpex.Preferences:order"
  """
  def order(live_resource) when is_atom(live_resource) do
    Key.resource_key(live_resource, "order")
  end

  @doc """
  Key for a resource's persisted filter selections.

  ## Examples

      iex> Backpex.Preferences.Keys.filters(Backpex.Preferences)
      "resource:Backpex.Preferences:filters"
  """
  def filters(live_resource) when is_atom(live_resource) do
    Key.resource_key(live_resource, "filters")
  end

  @doc """
  Key for a resource's metrics visibility toggle.

  ## Examples

      iex> Backpex.Preferences.Keys.metrics_visible(Backpex.Preferences)
      "resource:Backpex.Preferences:metrics_visible"
  """
  def metrics_visible(live_resource) when is_atom(live_resource) do
    Key.resource_key(live_resource, "metrics_visible")
  end

  @doc """
  Whether `value` is shaped the way the built-in reader for `key` expects.

  Client-supplied preference values reach the server on two paths the browser
  fully controls: the LiveView connect params and the `backpex_prefs` cookie
  (see `Backpex.Preferences.LiveView`). Both are overlaid on reads, so a
  wrong-typed value would flow straight into a render — and a render is not
  allowed to crash on browser input. `not "false"` raises, and so does
  `Map.get/3` on a binary, which would turn a single planted cookie into an
  HTTP 500 on every page for as long as the cookie lives.

  This is a *shape* gate, not an authorization gate: it asks only whether the
  built-in reader for this key can consume the value without raising. Values
  for keys Backpex does not own (`"custom."` and unknown `resource:` suffixes)
  pass through — Backpex cannot know their shape, so a host that reads its own
  keys out of the overlay must tolerate whatever the browser can send. There
  is no registration API for additional top-level prefixes; application-owned
  overlay keys belong under `"custom."`.

  Writes are checked against the *whole path*, not just the leaf. Adapters
  store at whatever depth they are given, so a key naming an interior node of
  a built-in path (`"global.sidebar_section"`) or a node below a built-in leaf
  (`"global.theme.x"`) would replace that leaf's value with a differently
  shaped one that no leaf check ever saw. Those keys are rejected.

  ## Examples

      iex> Backpex.Preferences.Keys.valid_value?("global.sidebar_open", false)
      true

      iex> Backpex.Preferences.Keys.valid_value?("global.sidebar_open", "false")
      false

      iex> Backpex.Preferences.Keys.valid_value?("custom.acme.anything", %{"a" => 1})
      true

  A key that would retype a built-in leaf from above or below is refused:

      iex> Backpex.Preferences.Keys.valid_value?("global.sidebar_section", %{"blog" => %{}})
      false

      iex> Backpex.Preferences.Keys.valid_value?("global.sidebar_section.blog.deep", true)
      false

      iex> Backpex.Preferences.Keys.valid_value?("global", %{"theme" => %{}})
      false

      iex> Backpex.Preferences.Keys.valid_value?("resource:MyApp.UserLive:columns:x", true)
      false

  Section states themselves are unaffected:

      iex> Backpex.Preferences.Keys.valid_value?("global.sidebar_section.blog", false)
      true
  """
  def valid_value?(key, value) when is_binary(key) do
    key |> Key.parse() |> shape(value)
  end

  def valid_value?(_key, _value), do: false

  defp shape(["global", "theme"], value), do: is_binary(value)
  defp shape(["global", "sidebar_open"], value), do: is_boolean(value)
  defp shape(["global", "sidebar_section", _id], value), do: is_boolean(value)
  defp shape(["resource", _module, "columns"], value), do: boolean_map?(value)
  defp shape(["resource", _module, "metrics_visible"], value), do: is_boolean(value)
  defp shape(["resource", _module, suffix], value) when suffix in ["order", "filters"], do: string_keyed_map?(value)

  # A write that lands on an interior node of a built-in path — or below a
  # built-in leaf — retypes that leaf without ever being measured against it.
  # `Backpex.Preferences.Adapters.Session.deep_put/3` writes at whatever depth
  # it is handed, so `"global.sidebar_section"` carrying `%{"blog" => %{}}`
  # installs a map where the section reader expects a boolean, and
  # `"global.theme.x"` turns the theme into one. Neither key can be expressed
  # as a leaf clause above, so reject them here rather than let the catch-all
  # wave them through.
  defp shape(["global"], _value), do: false
  defp shape(["global", segment | _rest], _value) when segment in @global_segments, do: false
  defp shape(["resource"], _value), do: false
  defp shape(["resource", _module], _value), do: false
  defp shape(["resource", _module, segment | _rest], _value) when segment in @resource_segments, do: false

  defp shape(_segments, _value), do: true

  defp boolean_map?(value) do
    string_keyed_map?(value) and Enum.all?(value, fn {_field, active} -> is_boolean(active) end)
  end

  defp string_keyed_map?(value) do
    is_map(value) and not is_struct(value) and Enum.all?(value, fn {key, _value} -> is_binary(key) end)
  end
end
