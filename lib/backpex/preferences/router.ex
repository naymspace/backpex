defmodule Backpex.Preferences.Router do
  @moduledoc """
  Maps a preference key to the adapter configured to handle it.

  ## Route format

  A route is `{pattern, adapter_module, adapter_opts}` where `pattern` is
  either:

  - an exact key like `"global.theme"`;
  - a prefix wildcard like `"resource.*"` (matches any key whose first segment
    is `"resource"`);
  - the atom `:default` (fallback route used when nothing else matches).

  ## Match strategy

  Longest-prefix-first: among matching patterns the one with the most segments
  wins. This guarantees specific patterns override general ones regardless of
  the order they appear in config. The `:default` pattern only wins when no
  other pattern matches.

  ## Configuration

      config :backpex, Backpex.Preferences,
        adapters: [
          {"global.*",   Backpex.Preferences.Adapters.Session, []},
          {"resource.*", MyApp.Preferences.EctoAdapter, repo: MyApp.Repo},
          {:default,     Backpex.Preferences.Adapters.Session, []}
        ]

  When no `:adapters` config is set, the router falls back to a single
  `{:default, Backpex.Preferences.Adapters.Session, []}` route so the zero-
  config behavior matches the legacy single-adapter implementation.
  """

  alias Backpex.Preferences.Key

  @type pattern :: String.t() | :default
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
  """
  @spec resolve(String.t()) :: {module(), keyword()}
  @spec resolve(String.t(), [route()]) :: {module(), keyword()}
  def resolve(key, routes \\ routes()) when is_binary(key) do
    case best_match(key, normalize(routes)) do
      nil ->
        raise ArgumentError,
              "no Backpex.Preferences adapter matches key #{inspect(key)}; " <>
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

  defp normalize(routes) do
    Enum.map(routes, fn
      {pattern, module} when is_atom(module) -> {pattern, module, []}
      {pattern, module, opts} when is_atom(module) and is_list(opts) -> {pattern, module, opts}
    end)
  end

  defp best_match(key, routes) do
    routes
    |> Enum.filter(&matches?(&1, key))
    |> Enum.max_by(&specificity/1, fn -> nil end)
  end

  defp matches?({:default, _module, _opts}, _key), do: true
  defp matches?({pattern, _module, _opts}, key) when is_binary(pattern), do: Key.match?(pattern, key)

  defp specificity({:default, _module, _opts}), do: -1

  defp specificity({pattern, _module, _opts}) when is_binary(pattern) do
    case String.split(pattern, ".") do
      [_single] -> 100
      segments -> length(segments) * 10 - if(List.last(segments) == "*", do: 1, else: 0)
    end
  end
end
