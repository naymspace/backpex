defmodule Backpex.Preferences.Router do
  @moduledoc """
  Maps a preference key to the adapter configured to handle it.

  ## Route format

  A route is `{pattern, adapter_module, adapter_opts}` where `pattern` is one
  of:

  - an exact key like `"global.theme"`;
  - a prefix wildcard like `"resource.*"` (matches any key whose first segment
    is `"resource"`);
  - a 1-arity function `(String.t() -> boolean())` invoked with the full key
    string; useful as an escape hatch for cross-cutting carve-outs that
    trailing-wildcard patterns cannot express (e.g. "every key ending in
    `:columns`");
  - the atom `:default` (fallback route used when nothing else matches).

  ## Match strategy

  **Match functions are the most specific route type.** A match function
  always beats any string pattern and `:default`, regardless of how specific
  the string pattern looks — the user wrote imperative matching code, so we
  assume they know what they're doing. When two match functions both return
  `true` for the same key, the one that appears **first in config order**
  wins (this differs from the longest-prefix rule that applies to string
  patterns).

  For string patterns, longest-prefix-first still applies: among matching
  strings the one with the most segments wins, with exact matches beating
  same-depth wildcards. This guarantees specific patterns override general
  ones regardless of the order they appear in config. The `:default` pattern
  only wins when no other pattern matches.

  ## Configuration

      config :backpex, Backpex.Preferences,
        adapters: [
          # Match funs: cross-cutting carve-outs (most specific tier)
          {&String.ends_with?(&1, ":columns"), Backpex.Preferences.Adapters.Session, []},
          {"global.*",   Backpex.Preferences.Adapters.Session, []},
          {"resource.*", MyApp.Preferences.EctoAdapter, repo: MyApp.Repo},
          {:default,     Backpex.Preferences.Adapters.Session, []}
        ]

  When no `:adapters` config is set, the router falls back to a single
  `{:default, Backpex.Preferences.Adapters.Session, []}` route so the zero-
  config behavior routes every key to the Session adapter.

  ## Prefix vs. key resolution

  Point lookups use `resolve/1,2` — they treat the argument as a complete key
  and pick the most specific matching pattern.

  Subtree reads (`Backpex.Preferences.get_map/3`) use `resolve_prefix/1,2` —
  they treat the argument as a namespace and pick the adapter that owns the
  entire subtree. See `resolve_prefix/2` for the matching rules.

  **Match-function routes are excluded from `resolve_prefix/1,2`.** A function
  that matches individual keys (e.g. every key ending in `:columns`) cannot
  cleanly answer "does this function own the subtree rooted at Q?" — it may
  match some keys under Q but not others, which is at odds with the
  single-owner semantics of `get_map`. Only string patterns and `:default`
  participate in subtree owner lookups.
  """

  alias Backpex.Preferences.Key

  @type pattern :: String.t() | :default | (String.t() -> boolean())
  @type route :: {pattern(), module(), keyword()}

  @doc """
  Loads the configured routes, falling back to a Session-adapter default when
  no config is set.
  """
  @spec routes() :: [route()]
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

  Exposed as a public function so `Backpex.Preferences` and test helpers can
  reuse it without re-implementing the match logic.

  ## Examples

      iex> routes = [
      ...>   {"global.*", Backpex.Preferences.Adapters.Session, []},
      ...>   {:default, Backpex.Preferences.Adapters.Session, []}
      ...> ]
      iex> Backpex.Preferences.Router.resolve("global.theme", routes)
      {Backpex.Preferences.Adapters.Session, []}
  """
  @spec resolve(String.t()) :: {module(), keyword()}
  @spec resolve(String.t(), [route()]) :: {module(), keyword()}
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
  Returns the `{module, opts}` that owns the subtree rooted at `prefix`.

  Unlike `resolve/1`, which treats its argument as a complete key, this
  function treats `prefix` as a **namespace** and asks "which adapter is
  responsible for keys under this prefix?"

  A route pattern `P` matches prefix `Q` when:

  - `P` is the exact string `Q` — e.g., route `"global.theme"` matches prefix
    `"global.theme"`; or
  - `P` is a wildcard `"X.*"` whose prefix segments are `Q`'s segments (the
    route is rooted exactly at `Q`); or
  - `P` is a wildcard `"X.*"` whose prefix segments are an ancestor of `Q`
    (the route covers a superset of `Q`'s subtree); or
  - `P` is a wildcard `"X.*"` whose prefix segments are a descendant of `Q`
    (the route lives strictly inside `Q`'s subtree); or
  - `P` is `:default` (catch-all).

  Among matching routes the most-specific one wins — the route whose prefix
  equals `Q` beats an ancestor-rooted wildcard, which in turn beats a
  descendant-rooted wildcard at greater depth, which beats `:default`.

  Returns `{module, opts}` or raises `ArgumentError` when nothing matches.

  ## Examples

      iex> routes = [
      ...>   {"resource.*", Backpex.Preferences.Adapters.Session, []},
      ...>   {:default, Backpex.Preferences.Adapters.Session, []}
      ...> ]
      iex> Backpex.Preferences.Router.resolve_prefix("resource", routes)
      {Backpex.Preferences.Adapters.Session, []}
  """
  @spec resolve_prefix(String.t()) :: {module(), keyword()}
  @spec resolve_prefix(String.t(), [route()]) :: {module(), keyword()}
  def resolve_prefix(prefix, routes \\ routes()) when is_binary(prefix) do
    normalized = normalize(routes)

    if normalized == [] do
      raise ArgumentError,
            "no Backpex.Preferences adapters configured; " <>
              "set :adapters under config :backpex, Backpex.Preferences, or omit the config " <>
              "to use the default Session adapter"
    end

    case best_prefix_match(prefix, normalized) do
      nil ->
        raise ArgumentError,
              "no Backpex.Preferences adapter matches prefix #{inspect(prefix)}; " <>
                "configure a :default route under config :backpex, Backpex.Preferences, adapters: [...]"

      {_pattern, module, opts} ->
        {module, opts}
    end
  end

  @doc false
  @spec default_routes() :: [route()]
  def default_routes do
    [{:default, Backpex.Preferences.Adapters.Session, []}]
  end

  @doc """
  Normalizes a raw route list, canonicalizing two-tuple entries to three-tuple
  form and validating shape.

  Raises `ArgumentError` with a descriptive message for malformed entries and
  for configurations where two wildcard routes with different adapters sit in
  an ancestor/descendant relationship that cannot be unambiguously resolved
  (see module docs).
  """
  @spec normalize([term()]) :: [route()]
  def normalize(routes) when is_list(routes) do
    normalized = Enum.map(routes, &validate_route/1)
    :ok = validate_no_conflicts!(normalized)
    normalized
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
            "where pattern is :default, a string, or a 1-arity function, and " <>
            "adapter_module is a module."
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

  defp validate_pattern!(pattern, _entry) when is_binary(pattern) do
    if pattern == "" do
      raise ArgumentError, "Backpex.Preferences route pattern must not be an empty string"
    end

    :ok
  end

  defp validate_pattern!(pattern, _entry) when is_function(pattern, 1), do: :ok

  defp validate_pattern!(pattern, _entry) when is_function(pattern) do
    {:arity, arity} = Function.info(pattern, :arity)

    raise ArgumentError,
          "Backpex.Preferences route match function must be arity 1 " <>
            "(receives the preference key string and returns boolean), got arity " <>
            Integer.to_string(arity) <> "."
  end

  defp validate_pattern!(other, _entry) do
    raise ArgumentError,
          "invalid Backpex.Preferences route pattern: " <>
            inspect(other) <>
            ". Expected a string like \"resource.*\", a 1-arity function, or the atom :default."
  end

  # Raises when two wildcard routes with different adapters have prefix
  # portions in an ancestor/descendant relationship in a way that makes a
  # later-listed route broader than an earlier-listed one — a pattern that
  # almost always indicates a misauthored config (the broader route swallows
  # the narrower one for any prefix lookup at the ancestor level).
  defp validate_no_conflicts!(routes) do
    wildcards = extract_wildcards(routes)

    Enum.reduce_while(wildcards, :ok, fn a, :ok ->
      case Enum.find(wildcards, &conflicting_pair?(a, &1)) do
        nil -> {:cont, :ok}
        b -> {:halt, raise_conflict!(a, b)}
      end
    end)
  end

  defp extract_wildcards(routes) do
    routes
    |> Enum.with_index()
    |> Enum.flat_map(&to_wildcard_entry/1)
  end

  defp to_wildcard_entry({{pattern, module, _opts}, index}) when is_binary(pattern) do
    case wildcard_prefix_segments(pattern) do
      nil -> []
      segs -> [{segs, pattern, module, index}]
    end
  end

  defp to_wildcard_entry(_other), do: []

  # A is earlier and narrower/equal; B is later and strictly broader; different
  # adapters.
  defp conflicting_pair?({segs_a, _pa, mod_a, idx_a}, {segs_b, _pb, mod_b, idx_b}) do
    idx_b > idx_a and mod_a != mod_b and proper_prefix?(segs_b, segs_a)
  end

  defp raise_conflict!({_segs_a, pattern_a, module_a, _idx_a}, {_segs_b, pattern_b, module_b, _idx_b}) do
    raise ArgumentError,
          "conflicting Backpex.Preferences routes: #{inspect(pattern_b)} " <>
            "(adapter #{inspect(module_b)}) covers the subtree already owned by " <>
            "#{inspect(pattern_a)} (adapter #{inspect(module_a)}); reorder so the " <>
            "broader pattern comes first, or point both routes at the same adapter."
  end

  # Returns the prefix segments of a wildcard pattern ("X.Y.*" → ["X", "Y"]),
  # or nil when the pattern is not a wildcard (no trailing "*").
  defp wildcard_prefix_segments(pattern) when is_binary(pattern) do
    segments = String.split(pattern, ".")

    case List.last(segments) do
      "*" when length(segments) > 1 -> Enum.drop(segments, -1)
      _other -> nil
    end
  end

  # True when `a` is a proper prefix of `b` (strictly shorter, matching at
  # every position of `a`). Equal lists are not a proper prefix.
  defp proper_prefix?(a, b) when length(a) < length(b) do
    Enum.take(b, length(a)) == a
  end

  defp proper_prefix?(_a, _b), do: false

  defp best_match(key, routes) do
    routes
    |> Enum.filter(&matches?(&1, key))
    |> Enum.max_by(&specificity/1, fn -> nil end)
  end

  defp matches?({:default, _module, _opts}, _key), do: true

  defp matches?({fun, _module, _opts}, key) when is_function(fun, 1), do: fun.(key)

  defp matches?({pattern, _module, _opts}, key) when is_binary(pattern) do
    case wildcard_prefix_segments(pattern) do
      nil ->
        # Delegate single-segment wildcards ("resource.*") and exact patterns to Key.match?/2
        # so colon-encoded module names ("resource:MyApp.Foo:columns") split against the
        # correct separator — segment-equality on dot-split would fail for that form.
        Key.match?(pattern, key)

      wildcard_segs ->
        # Multi-segment wildcard ("resource.foo.*"): match when the key's
        # leading segments equal the wildcard's prefix segments.
        key_segs = Key.parse(key)
        length(key_segs) >= length(wildcard_segs) and Enum.take(key_segs, length(wildcard_segs)) == wildcard_segs
    end
  end

  defp best_prefix_match(prefix, routes) do
    prefix_segments = String.split(prefix, ".")

    # Exclude match-function routes from subtree owner lookups. A function that
    # matches individual keys (e.g. every key ending in ":columns") cannot
    # cleanly own a subtree — it may match some keys under the query prefix
    # but not others, which contradicts the single-owner semantics that
    # get_map/3 relies on. Only string patterns and :default participate here.
    routes
    |> Enum.filter(&(not match_fun_route?(&1) and prefix_matches?(&1, prefix, prefix_segments)))
    |> Enum.max_by(&prefix_specificity(&1, prefix_segments), fn -> nil end)
  end

  defp match_fun_route?({fun, _module, _opts}) when is_function(fun, 1), do: true
  defp match_fun_route?(_route), do: false

  defp prefix_matches?({:default, _module, _opts}, _prefix, _prefix_segments), do: true

  defp prefix_matches?({pattern, _module, _opts}, prefix, prefix_segments) when is_binary(pattern) do
    case wildcard_prefix_segments(pattern) do
      nil ->
        # Exact pattern: matches only when identical to the query prefix.
        pattern == prefix

      wildcard_segs ->
        # Wildcard P matches prefix Q when P's prefix segments and Q are on
        # the same lineage in the tree: equal, or one an ancestor of the
        # other.
        lineage?(wildcard_segs, prefix_segments)
    end
  end

  defp lineage?(a, b) do
    a == b or proper_prefix?(a, b) or proper_prefix?(b, a)
  end

  # Specificity for a prefix match against query segments `Q`. Tuple is
  # designed so `Enum.max_by/2` picks the most specific match. Tiers (higher
  # beats lower):
  #
  #   4 — exact pattern equal to Q
  #   3 — wildcard whose prefix equals Q (route is rooted at Q)
  #   2 — wildcard whose prefix is an ancestor of Q (route covers a superset)
  #   1 — wildcard whose prefix is a descendant of Q (route is inside Q)
  #   0 — :default catch-all
  #
  # Within tier 2 (ancestor), deeper (longer) prefix wins — it's closer to Q.
  # Within tier 1 (descendant), shallower (shorter) prefix wins — it's closer
  # to Q from above, so we negate the length to invert the sort.
  defp prefix_specificity({:default, _module, _opts}, _query_segs), do: {0, 0}

  defp prefix_specificity({pattern, _module, _opts}, query_segs) when is_binary(pattern) do
    case wildcard_prefix_segments(pattern) do
      nil ->
        {4, length(query_segs)}

      wildcard_segs ->
        cond do
          wildcard_segs == query_segs ->
            {3, length(wildcard_segs)}

          proper_prefix?(wildcard_segs, query_segs) ->
            {2, length(wildcard_segs)}

          proper_prefix?(query_segs, wildcard_segs) ->
            {1, -length(wildcard_segs)}

          true ->
            raise "unreachable: no tier matched for pattern #{inspect(pattern)} " <>
                    "against query #{inspect(query_segs)}"
        end
    end
  end

  @doc """
  Returns a tuple representing the specificity of a route pattern.

  The tuple is designed so that `Enum.sort_by/2` (and `Enum.max_by/2`) sort
  in the correct precedence order. Tiers (higher beats lower):

    * 2 — match functions (most specific; always win over strings and :default)
    * 1 — string patterns (exact beats wildcard at the same effective depth;
      longer patterns beat shorter ones)
    * 0 — `:default` catch-all

  All match-function routes share the same tuple `{2, 0, 0}`, so when two
  functions both match a key, `Enum.max_by/2` returns the one it encounters
  first. Combined with `Enum.filter/2` preserving list order, this yields
  "first in config order wins" for match-function ties.

  The exact tuple shape is an implementation detail; rely only on ordering.

  ## Examples

      iex> Backpex.Preferences.Router.specificity({"global.theme", Foo, []}) >
      ...>   Backpex.Preferences.Router.specificity({"global.*", Foo, []})
      true

      iex> Backpex.Preferences.Router.specificity({"resource.*", Foo, []}) >
      ...>   Backpex.Preferences.Router.specificity({:default, Foo, []})
      true

      iex> Backpex.Preferences.Router.specificity({fn _ -> true end, Foo, []}) >
      ...>   Backpex.Preferences.Router.specificity({"global.theme", Foo, []})
      true
  """
  @spec specificity(route()) :: tuple()
  def specificity({:default, _module, _opts}), do: {0, 0, 0}

  def specificity({fun, _module, _opts}) when is_function(fun, 1), do: {2, 0, 0}

  def specificity({pattern, _module, _opts}) when is_binary(pattern) do
    segments = String.split(pattern, ".")
    wildcard? = List.last(segments) == "*"

    # Measure "effective depth" — exact patterns use their own segment count,
    # wildcards count only the leading prefix segments (dropping the trailing
    # "*"). This way an exact "global.theme" at depth 2 beats the wildcard
    # "global.*" whose prefix is at depth 1.
    depth = if wildcard?, do: length(segments) - 1, else: length(segments)

    # Sort order: named patterns beat :default, longer effective depth beats
    # shorter, exact matches beat wildcards at the same effective depth.
    {1, depth, if(wildcard?, do: 0, else: 1)}
  end
end
