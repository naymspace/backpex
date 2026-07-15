defmodule Backpex.Preferences.Router do
  @moduledoc """
  Maps a preference key to the adapter configured to handle it.

  ## Route format

  A route is `{pattern, adapter_module}` or `{pattern, adapter_module,
  adapter_opts}`, where `pattern` is one of:

  - an **exact key** like `"global.theme"`, matched by equality;
  - a **wildcard** like `"resource.*"` — a prefix followed by a trailing
    `"*"`, matching every key under that prefix (and the prefix itself);
  - the atom **`:default`**, the fallback used when nothing else matches.

  Wildcards are segmented by `Backpex.Preferences.Key.parse/1`, the same
  function that segments keys. A pattern therefore addresses exactly the
  segments a key is built from, including the colon-separated form used for
  per-resource keys:

      Backpex.Preferences.Keys.columns(MyApp.UserLive)
      #=> "resource:MyApp.UserLive:columns"

      # covered by any of:
      "resource.*"                    # every resource
      "resource:MyApp.UserLive:*"     # just this resource
      "resource:MyApp.UserLive:columns"

  `"*"` is only meaningful as the final segment. Any other placement (`"*"`
  alone, `"resource.*.columns"`, `"res*"`) is a configuration error and
  raises at boot — it could never match a key, and a pattern that silently
  matches nothing is worse than one that refuses to start.

  ## Match strategy

  Longest-prefix-first: among the matching patterns the one with the most
  segments wins, and an exact pattern beats a wildcard at the same depth.
  Specificity alone decides, so a narrow route overrides a broad one no
  matter which order they appear in config. `:default` wins only when
  nothing else matches.

  ## Configuration

      config :backpex, Backpex.Preferences,
        adapters: [
          {"global.*",   Backpex.Preferences.Adapters.Session, []},
          {"resource.*", MyApp.Preferences.EctoAdapter, repo: MyApp.Repo},
          {:default,     Backpex.Preferences.Adapters.Session, []}
        ]

  With no `:adapters` config the router falls back to a single
  `{:default, Backpex.Preferences.Adapters.Session, []}` route, so the
  zero-config behavior routes every key to the Session adapter.
  """

  alias Backpex.Preferences.Key

  @type pattern :: String.t() | :default
  @type route :: {pattern(), module(), keyword()}

  @doc """
  Loads the configured routes, falling back to a Session-adapter default when
  no config is set.
  """
  def routes do
    configured =
      :backpex
      |> Application.get_env(Backpex.Preferences, [])
      |> Keyword.get(:adapters)

    case configured do
      nil -> default_routes()
      [] -> default_routes()
      list when is_list(list) -> normalize(list)
    end
  end

  @doc """
  Returns the matching `{module, opts}` for `key`, or raises if no route
  (including `:default`) matches.

  This is the resolution entry point for point reads and writes. Subtree reads
  use `resolve_subtree/2` because exact routes and nested wildcards can carve
  keys beneath a broader prefix into another adapter.

  ## Examples

      iex> routes = [
      ...>   {"global.*", Backpex.Preferences.Adapters.Session, []},
      ...>   {:default, Backpex.Preferences.Adapters.Session, []}
      ...> ]
      iex> Backpex.Preferences.Router.resolve("global.theme", routes)
      {Backpex.Preferences.Adapters.Session, []}

      iex> routes = [
      ...>   {"resource:MyApp.UserLive:*", MyApp.EctoAdapter, repo: MyApp.Repo},
      ...>   {"resource.*", Backpex.Preferences.Adapters.Session, []}
      ...> ]
      iex> Backpex.Preferences.Router.resolve("resource:MyApp.UserLive:columns", routes)
      {MyApp.EctoAdapter, [repo: MyApp.Repo]}
  """
  def resolve(key, routes \\ routes()) when is_binary(key) do
    normalized = normalize(routes)

    if normalized == [] do
      raise ArgumentError,
            "no Backpex.Preferences adapters configured; " <>
              "set :adapters under config :backpex, Backpex.Preferences, or omit the config " <>
              "to use the default Session adapter"
    end

    case best_match(key, normalized) do
      nil ->
        raise ArgumentError,
              "no Backpex.Preferences adapter matches key #{inspect(key)}; " <>
                "configure a :default route under config :backpex, Backpex.Preferences, adapters: [...]"

      {_pattern, module, opts} ->
        {module, opts}
    end
  end

  @doc """
  Returns the routes that can own `prefix` or keys beneath it, ordered from
  broadest to most specific.

  A subtree can span adapters when an exact route or nested wildcard carves a
  key out of a broader route. `Backpex.Preferences.get_map/3` reads these
  routes in order so the more specific route wins for the part it owns.

  ## Examples

      iex> routes = [
      ...>   {"global.sidebar_section.blog", MyApp.DatabaseAdapter, []},
      ...>   {"global.*", Backpex.Preferences.Adapters.Session, []}
      ...> ]
      iex> Backpex.Preferences.Router.resolve_subtree("global.sidebar_section", routes)
      [
        {"global.*", Backpex.Preferences.Adapters.Session, []},
        {"global.sidebar_section.blog", MyApp.DatabaseAdapter, []}
      ]
  """
  def resolve_subtree(prefix, routes \\ routes()) when is_binary(prefix) do
    normalized = normalize(routes)
    prefix_segments = Key.parse(prefix)
    base_route = subtree_base_route(prefix_segments, normalized)

    nested_routes =
      Enum.filter(normalized, fn
        {:default, _module, _opts} ->
          false

        {pattern, _module, _opts} ->
          pattern
          |> route_prefix()
          |> descendant_of?(prefix_segments)
      end)

    routes =
      [base_route | nested_routes]
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.sort_by(&specificity/1)

    if routes == [] do
      raise ArgumentError,
            "no Backpex.Preferences adapter matches prefix #{inspect(prefix)} or any key beneath it; " <>
              "configure a matching route or a :default route under " <>
              "config :backpex, Backpex.Preferences, adapters: [...]"
    end

    routes
  end

  @doc false
  def default_routes do
    [{:default, Backpex.Preferences.Adapters.Session, []}]
  end

  @doc """
  Normalizes a raw route list, canonicalizing two-tuple entries to three-tuple
  form and validating shape.

  Raises `ArgumentError` with a descriptive message for malformed entries: a
  bad adapter module, an unusable pattern, or a wildcard that could never
  match a key.
  """
  def normalize(routes) when is_list(routes) do
    Enum.map(routes, &validate_route/1)
  end

  defp validate_route({pattern, module}) when is_atom(module) do
    validate_pattern!(pattern, {pattern, module})
    validate_module!(module, {pattern, module})
    {pattern, module, []}
  end

  defp validate_route({pattern, module, opts}) when is_atom(module) and is_list(opts) do
    validate_pattern!(pattern, {pattern, module, opts})
    validate_module!(module, {pattern, module, opts})
    {pattern, module, opts}
  end

  defp validate_route(other) do
    raise ArgumentError,
          "invalid Backpex.Preferences route entry: " <>
            inspect(other) <>
            ". Expected {pattern, adapter_module} or {pattern, adapter_module, opts}, " <>
            "where pattern is :default or a string, and adapter_module is a module."
  end

  # Distinguishes a module alias (e.g. `MyApp.Foo` → `:"Elixir.MyApp.Foo"`)
  # from a plain atom (e.g. `:not_a_module`) so misconfigured routes fail at
  # config time with a clear message instead of crashing downstream.
  defp validate_module!(module, entry) when is_atom(module) do
    cond do
      is_nil(module) ->
        raise ArgumentError,
              "expected adapter module for route #{inspect(entry)}, got: nil"

      module_alias?(module) ->
        :ok

      true ->
        raise ArgumentError,
              "expected adapter module for route #{inspect(entry)}, got: " <> inspect(module)
    end
  end

  defp module_alias?(atom) when is_atom(atom) do
    case Atom.to_string(atom) do
      "Elixir." <> _rest -> true
      _other -> false
    end
  end

  defp validate_pattern!(:default, _entry), do: :ok

  defp validate_pattern!(pattern, entry) when is_binary(pattern) do
    cond do
      pattern == "" ->
        raise ArgumentError, "Backpex.Preferences route pattern must not be an empty string"

      not String.contains?(pattern, "*") ->
        :ok

      matchable_wildcard?(pattern) ->
        :ok

      true ->
        raise ArgumentError,
              "invalid Backpex.Preferences wildcard pattern #{inspect(pattern)} in route #{inspect(entry)}. " <>
                "\"*\" is only valid as the final segment, after at least one leading segment — " <>
                ~s(e.g. "global.*" or "resource:MyApp.UserLive:*". ) <>
                "Use :default to match every key."
    end
  end

  defp validate_pattern!(other, _entry) do
    raise ArgumentError,
          "invalid Backpex.Preferences route pattern: " <>
            inspect(other) <>
            ". Expected a string like \"resource.*\" or the atom :default."
  end

  # A wildcard is usable only when "*" is the whole final segment and every
  # leading segment is a literal. Anything else ("*" alone, "resource.*.columns",
  # "res*") can never match a key, so it is rejected rather than left to match
  # nothing at runtime.
  defp matchable_wildcard?(pattern) do
    case Key.wildcard_prefix(pattern) do
      nil -> false
      prefix_segments -> Enum.all?(prefix_segments, &(&1 != "" and not String.contains?(&1, "*")))
    end
  end

  defp best_match(key, routes) do
    routes
    |> Enum.filter(&matches?(&1, key))
    |> Enum.max_by(&specificity/1, fn -> nil end)
  end

  defp matches?({:default, _module, _opts}, _key), do: true
  defp matches?({pattern, _module, _opts}, key) when is_binary(pattern), do: Key.match?(pattern, key)

  defp subtree_base_route(prefix_segments, routes) do
    routes
    |> Enum.filter(fn
      {pattern, _module, _opts} when is_binary(pattern) ->
        case Key.wildcard_prefix(pattern) do
          nil -> false
          wildcard_prefix -> prefix_of?(wildcard_prefix, prefix_segments)
        end

      {:default, _module, _opts} ->
        false
    end)
    |> Enum.max_by(&specificity/1, fn -> Enum.find(routes, &match?({:default, _, _}, &1)) end)
  end

  defp route_prefix(pattern), do: Key.wildcard_prefix(pattern) || Key.parse(pattern)

  defp descendant_of?(route_segments, prefix_segments), do: prefix_of?(prefix_segments, route_segments)

  defp prefix_of?(prefix_segments, segments) do
    length(segments) >= length(prefix_segments) and
      Enum.take(segments, length(prefix_segments)) == prefix_segments
  end

  # Ranks a route so `Enum.max_by/2` picks the most specific match. Tiers
  # (higher beats lower):
  #
  #   {1, depth, 1} — exact pattern, `depth` segments
  #   {1, depth, 0} — wildcard rooted at `depth` segments
  #   {0, 0, 0}     — :default catch-all
  #
  # Longer effective depth beats shorter, and at equal depth an exact pattern
  # beats a wildcard — so "global.theme" wins over "global.*", which wins over
  # :default, independent of config order.
  defp specificity({:default, _module, _opts}), do: {0, 0, 0}

  defp specificity({pattern, _module, _opts}) when is_binary(pattern) do
    case Key.wildcard_prefix(pattern) do
      nil -> {1, length(Key.parse(pattern)), 1}
      prefix_segments -> {1, length(prefix_segments), 0}
    end
  end
end
