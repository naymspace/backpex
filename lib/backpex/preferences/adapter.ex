defmodule Backpex.Preferences.Adapter do
  @moduledoc """
  Behavior implemented by Backpex preference storage adapters.

  `Backpex.Preferences` dispatches each call to an adapter selected by the
  key's prefix. Backpex ships with `Backpex.Preferences.Adapters.Session` by default and
  configure others per prefix:

      config :backpex, Backpex.Preferences,
        adapters: [
          {"global.*",   Backpex.Preferences.Adapters.Session, []},
          {"resource.*", Backpex.Preferences.Adapters.Ecto,
           repo: MyApp.Repo, schema: MyApp.Preference, scope_fields: [:user_id, :tenant_id]},
          {:default,     Backpex.Preferences.Adapters.Session, []}
        ],
        scope: {MyAppWeb.PreferencesScope, :resolve, []}

  ## Return semantics

  The three atoms in the return types deserve a note:

  - `{:ok, :not_found}` — the adapter successfully determined that no value is
    stored for this key. `Backpex.Preferences.get/3` callers fall back to
    their `:default` option.
  - `{:error, :unscoped}` — the adapter needs a resolved preference scope (see
    `Backpex.Preferences.Context.scope`) and does not have one. Reads
    should be treated as "not found"; writes surface `{ok: false}` to the
    caller without crashing.
  - `{:error, :requires_http}` — the adapter can only write via a
    `%Plug.Conn{}` (e.g. the Session adapter writing to the session cookie)
    and was invoked from a context that has no conn (mount / socket). The
    server-side helper in `Backpex.Preferences` catches this and falls back to
    a `push_event/3` round-trip so the browser can retry via the HTTP
    endpoint.
  - `{:error, :too_large}` — the value would push the adapter's store past a
    size limit it cannot exceed (e.g. the ~4KB cookie session store). The
    write is refused whole; the previously stored value is untouched.
    `Backpex.PreferencesController` surfaces this as a `422`. An adapter with
    no meaningful size ceiling never returns it.

  ## Side-effect protocol

  A write describes what the caller should do rather than mutating the conn
  itself. `c:put/4` returns exactly one of:

  - `{:ok, :persisted}` — the adapter stored the value on its own (a database
    write) and needs nothing from the caller.
  - `{:ok, {:put_session, key, map}}` — the adapter needs the caller to put
    `map` under the given Phoenix session key.

  Keeping adapters side-effect-free this way lets them be exercised in unit
  tests without a conn and supports server-side writes that do not have one.

  `{:put_session, _, _}` can only be honored on a `%Plug.Conn{}`;
  `Plug.Session` is HTTP-only. An adapter that stores in the session must
  therefore return `{:error, :requires_http}` when it is called outside a
  controller, so the dispatcher can round-trip the write through the browser.
  """

  alias Backpex.Preferences.Context
  alias Backpex.Preferences.Key

  @typedoc """
  Work the caller is responsible for applying after `c:put/4`.

  Asks the caller to put `value` under `key` in the Phoenix session.
  """
  @type side_effect :: {:put_session, key :: String.t(), value :: map()}

  @typedoc """
  The outcome of a successful `c:put/4`.

  Either the adapter persisted the value itself (`:persisted`) or it needs
  the caller to apply a single side effect.
  """
  @type put_result :: :persisted | side_effect()

  @doc """
  Read a single key.

  Return `{:ok, :not_found}` when no value is stored; callers fall back to
  their `:default` option.
  """
  @callback get(ctx :: Context.t(), key :: String.t(), opts :: keyword()) ::
              {:ok, term()} | {:ok, :not_found} | {:error, :unscoped | term()}

  @doc """
  Read every value under `prefix` and return them as a nested map.

  The returned map mirrors the structure that a `get/3` at that prefix would
  have produced if there were a single nested value — i.e. it is keyed by the
  path segments that come after `prefix`, not by full dotted/coloned keys.
  """
  @callback get_map(ctx :: Context.t(), prefix :: String.t(), opts :: keyword()) ::
              {:ok, map()} | {:error, :unscoped | term()}

  @doc """
  Persist a value.

  Return `{:ok, :persisted}` when the adapter stored the value itself (a DB
  write), or `{:ok, {:put_session, key, map}}` to ask the caller to apply the
  one side effect the adapter cannot perform on its own (see the module docs).

  Refuse rather than emit a write the store cannot hold: an adapter with a
  size ceiling returns `{:error, :too_large}` when the value would breach it,
  leaving the stored value untouched.
  """
  @callback put(ctx :: Context.t(), key :: String.t(), value :: term(), opts :: keyword()) ::
              {:ok, put_result()} | {:error, :unscoped | :requires_http | :too_large | term()}

  @doc """
  Builds the nested map `c:get_map/3` must return from flat `{key, value}` rows.

  Stores that keep one entry per full key — a database table, Redis, ETS —
  cannot answer `c:get_map/3` directly: the callback is specified in terms of
  the nested shape a `c:get/3` at that prefix would have produced. Hand it
  every row whose key starts with `prefix` and it does the rest.

  Rows that are not descendants of `prefix` are dropped, so an over-broad
  fetch is safe. That matters more than it looks: SQL `LIKE` treats `_` as a
  wildcard, so a prefix such as `global.sidebar_section` also matches a stored
  `global.sidebarXsection.blog`. Matching happens on parsed key segments
  (`Backpex.Preferences.Key.parse/1`), never on raw string prefixes, so a key
  is only included when it shares a whole-segment boundary with `prefix`.

  A row whose key *is* `prefix` has nothing below it and is dropped too.

      iex> alias Backpex.Preferences.Adapter
      iex> Adapter.nest([{"global.sidebar_section.blog", true}], "global.sidebar_section")
      %{"blog" => true}

      iex> alias Backpex.Preferences.Adapter
      iex> Adapter.nest([{"global.sidebar_section.blog", true}], "global")
      %{"sidebar_section" => %{"blog" => true}}

      iex> alias Backpex.Preferences.Adapter
      iex> Adapter.nest([{"global.sidebarXsection.blog", true}], "global.sidebar_section")
      %{}
  """
  @spec nest([{String.t(), term()}], String.t()) :: map()
  def nest(rows, prefix) do
    prefix_path = Key.parse(prefix)

    Enum.reduce(rows, %{}, fn {key, value}, acc ->
      case relative_path(key, prefix_path) do
        [] -> acc
        path -> deep_put(acc, path, value)
      end
    end)
  end

  @doc """
  Writes `value` at `path` in a nested map, creating intermediate maps.

  A non-map sitting at an intermediate segment is replaced: preference keys
  form a tree, and a key deeper than an existing leaf wins over it.

      iex> Backpex.Preferences.Adapter.deep_put(%{}, ["a", "b"], 1)
      %{"a" => %{"b" => 1}}

      iex> Backpex.Preferences.Adapter.deep_put(%{"a" => 1}, ["a", "b"], 2)
      %{"a" => %{"b" => 2}}
  """
  @spec deep_put(map(), [String.t(), ...], term()) :: map()
  def deep_put(map, [key], value), do: Map.put(map, key, value)

  def deep_put(map, [key | path], value) do
    nested = if is_map(map[key]), do: map[key], else: %{}
    Map.put(map, key, deep_put(nested, path, value))
  end

  # Segments of `key` below `prefix_path`, or `[]` when `key` is not a strict
  # descendant of it. `Enum.split/2` plus the pin only matches on a whole
  # segment boundary, which is what rejects the `LIKE` over-match above.
  defp relative_path(key, prefix_path) do
    segments = Key.parse(key)

    case Enum.split(segments, length(prefix_path)) do
      {^prefix_path, path} -> path
      _other -> []
    end
  end
end
