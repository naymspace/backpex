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

  ## Self-check

  An `@after_compile` callback runs every 0-arity helper and pipes the
  result through `Backpex.Preferences.Key.validate/1`. If a built-in
  helper ever drifts to emit a key with an unknown prefix — say, a typo
  in a refactor — compilation fails immediately. 1-arity helpers are
  exercised by the companion test (`test/preferences/keys_validation_test.exs`).
  """

  alias Backpex.Preferences.Key

  @after_compile __MODULE__

  @doc false
  def __after_compile__(env, _bytecode) do
    for {name, 0} <- env.module.__info__(:functions),
        name not in [:__info__, :module_info] do
      key = apply(env.module, name, [])

      case Key.validate(key) do
        :ok ->
          :ok

        {:error, reason} ->
          raise CompileError,
            description:
              "#{inspect(env.module)}.#{name}/0 returned #{inspect(key)} which fails " <>
                "Backpex.Preferences.Key.validate/1 with #{inspect(reason)}. Known prefixes: " <>
                "#{inspect(Key.known_prefixes())}."
      end
    end

    :ok
  end

  @doc """
  Key for the global UI theme.

  ## Examples

      iex> Backpex.Preferences.Keys.theme()
      "global.theme"
  """
  @spec theme() :: String.t()
  def theme, do: "global.theme"

  @doc """
  Key for the global sidebar open/closed state.

  ## Examples

      iex> Backpex.Preferences.Keys.sidebar_open()
      "global.sidebar_open"
  """
  @spec sidebar_open() :: String.t()
  def sidebar_open, do: "global.sidebar_open"

  @doc """
  Prefix for per-section sidebar open/closed state.

  The prefix is used with `Backpex.Preferences.get_map/3` to read every
  section's state in one call. Individual section writes go through the JS
  `BackpexPreferences.set/2` helper as `"global.sidebar_section.<id>"`.

  ## Examples

      iex> Backpex.Preferences.Keys.sidebar_section_prefix()
      "global.sidebar_section"
  """
  @spec sidebar_section_prefix() :: String.t()
  def sidebar_section_prefix, do: "global.sidebar_section"

  @doc """
  Key for a resource's persisted column visibility.

  ## Examples

      iex> Backpex.Preferences.Keys.columns(Backpex.Preferences)
      "resource:Backpex.Preferences:columns"
  """
  @spec columns(module()) :: String.t()
  def columns(live_resource) when is_atom(live_resource) do
    Key.resource_key(live_resource, "columns")
  end

  @doc """
  Key for a resource's persisted sort order.

  ## Examples

      iex> Backpex.Preferences.Keys.order(Backpex.Preferences)
      "resource:Backpex.Preferences:order"
  """
  @spec order(module()) :: String.t()
  def order(live_resource) when is_atom(live_resource) do
    Key.resource_key(live_resource, "order")
  end

  @doc """
  Key for a resource's persisted filter selections.

  ## Examples

      iex> Backpex.Preferences.Keys.filters(Backpex.Preferences)
      "resource:Backpex.Preferences:filters"
  """
  @spec filters(module()) :: String.t()
  def filters(live_resource) when is_atom(live_resource) do
    Key.resource_key(live_resource, "filters")
  end

  @doc """
  Key for a resource's metrics visibility toggle.

  ## Examples

      iex> Backpex.Preferences.Keys.metrics_visible(Backpex.Preferences)
      "resource:Backpex.Preferences:metrics_visible"
  """
  @spec metrics_visible(module()) :: String.t()
  def metrics_visible(live_resource) when is_atom(live_resource) do
    Key.resource_key(live_resource, "metrics_visible")
  end
end
