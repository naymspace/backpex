defmodule Backpex.Preferences do
  @moduledoc """
  Unified preference management for Backpex.

  Reads and writes UI state (theme, sidebar open/closed, sidebar section
  expansion, per-resource column visibility, metric toggles, and user-defined
  keys) through a configurable **adapter**. The adapter is selected per key by
  a longest-prefix match against the configured routes (see
  `Backpex.Preferences.Router`), so different prefixes can live in different
  storage backends — e.g. `global.*` in the Phoenix session and `resource.*`
  in a per-user database table.

  ## Zero-config defaults

  With no `:backpex, Backpex.Preferences` config set, every key routes to
  `Backpex.Preferences.Adapters.Session`.

  ## Configuring per-prefix routing

      config :backpex, Backpex.Preferences,
        adapters: [
          {"global.*",   Backpex.Preferences.Adapters.Session, []},
          {"resource.*", MyApp.Preferences.EctoAdapter, repo: MyApp.Repo},
          {:default,     Backpex.Preferences.Adapters.Session, []}
        ],
        identity: {MyAppWeb.PreferencesIdentity, :resolve, []}

  ## Key format

  - `global.*` — application-wide preferences (theme, sidebar, ...).
  - `resource:<Module>:*` — per-resource preferences (columns, metrics, ...).
    Uses `:` as a separator so module-name dots don't split into extra
    segments (`Backpex.Preferences.Key`).
  - `custom.*` — user-defined preferences.

  ## Public API

    * `get/3` — read a single preference, with a `:default` fallback.
    * `get_map/3` — read every value under a prefix as a nested map.
    * `put/4` — write from a LiveView socket or `%Plug.Conn{}`.
    * `put_batch/3` — dispatch a list of writes (best-effort, first-error-wins;
      see the function docs for the partial-success semantics).
  """

  alias Backpex.Preferences.Adapters
  alias Backpex.Preferences.Context
  alias Backpex.Preferences.Key
  alias Backpex.Preferences.Keys
  alias Backpex.Preferences.LiveView, as: PreferenceLiveView
  alias Backpex.Preferences.Router
  alias Phoenix.LiveView.Socket

  require Logger

  @doc """
  Reads a preference. Falls back to `opts[:default]` when the value is
  missing or the adapter cannot identify the current user.

  Accepts a `%Backpex.Preferences.Context{}` or a bare Phoenix session map.
  The session-map form is convenient for call sites that only have a
  session on hand.

  ## Options

    * `:default` — returned when nothing is stored for `key` (default: `nil`).

  Extra options are forwarded to the adapter.

  ## Distinguishing "never set"

  With no `:default`, a missing value reads as `nil` — which separates "the
  user never set this" from "the user deliberately stored an empty value".
  An explicitly cleared `%{}` or `[]` is a real preference and must not be
  overwritten by an application default; this is how `persist: [:filters]`
  decides whether to apply a resource's filter defaults.

  The default Session adapter reserves `nil` for “not found”, so it cannot
  distinguish a stored `nil` from a missing key. Store a tagged value such as
  `%{"value" => nil}` when that distinction matters. A custom adapter that
  returns `{:ok, nil}` may preserve `nil`; with such an adapter, a sentinel
  default (for example `default: :__unset__`) distinguishes the missing case.

  ## Examples

      iex> session = %{"backpex_preferences" => %{"global" => %{"theme" => "dark"}}}
      iex> Backpex.Preferences.get(session, "global.theme")
      "dark"

      iex> Backpex.Preferences.get(%{}, "global.theme", default: "light")
      "light"
  """
  def get(ctx_or_session, key, opts \\ []) do
    default = Keyword.get(opts, :default)

    case client_fetch(ctx_or_session, key) do
      :error -> get_from_adapter(ctx_or_session, key, opts, default)
      {:ok, value} -> value
    end
  end

  defp get_from_adapter(ctx_or_session, key, opts, default) do
    case dispatch_get(ctx_or_session, key, opts) do
      {_module, {:ok, :not_found}} ->
        default

      {_module, {:ok, value}} ->
        value

      # `Backpex.Preferences.Adapter` defines `{:error, :unidentified}` on reads
      # as "treat as not found": the adapter needs a resolved user and has none.
      # That is an expected condition (anonymous visitors, background jobs), so
      # it falls back to the default silently rather than logging every read.
      {_module, {:error, :unidentified}} ->
        default

      {module, {:error, reason}} ->
        Logger.warning(
          "Backpex.Preferences: adapter #{inspect(module)} returned error on get/3 for key " <>
            "#{inspect(key)}: #{inspect(reason)}; falling back to default"
        )

        default
    end
  end

  @doc """
  Reads every value under `prefix` as a nested map.

  Keys in the returned map are relative to `prefix` (i.e. segments that
  follow the prefix). The adapter is free to store values however it likes,
  but the shape returned here matches what a single nested `get/3` at that
  prefix would have produced.

  Returns `%{}` when nothing is stored, the adapter cannot identify the user,
  or the adapter fails for any other reason.

  Client-overlay descendants are reconstructed only for dot-form keys by
  matching `prefix <> "."`. Adapter-backed colon-form subtrees remain readable,
  but pending client values for keys such as `resource:MyApp.PostLive:columns`
  are not merged into a `get_map/3` result. Use `get/3` for colon-form keys when
  client-overlay precedence is required.

  ## Examples

      iex> session = %{
      ...>   "backpex_preferences" => %{
      ...>     "global" => %{"sidebar_section" => %{"blog" => true, "users" => false}}
      ...>   }
      ...> }
      iex> Backpex.Preferences.get_map(session, "global.sidebar_section")
      %{"blog" => true, "users" => false}

      iex> Backpex.Preferences.get_map(%{}, "global.sidebar_section")
      %{}
  """
  def get_map(ctx_or_session, prefix, opts \\ []) do
    ctx = resolve_identity(Context.coerce(ctx_or_session))
    prefix_segments = Key.parse(prefix)

    {stored, _adapter_results} =
      prefix
      |> Router.resolve_subtree()
      |> Enum.reduce({%{}, %{}}, fn {_pattern, module, adapter_opts} = route, {acc, adapter_results} ->
        adapter_key = {module, adapter_opts}

        {route_map, adapter_results} =
          case Map.fetch(adapter_results, adapter_key) do
            {:ok, route_map} ->
              {route_map, adapter_results}

            :error ->
              route_map = read_subtree_route(route, ctx, prefix, opts)
              {route_map, Map.put(adapter_results, adapter_key, route_map)}
          end

        {merge_subtree_route(route_map, acc, prefix_segments, route), adapter_results}
      end)

    Map.merge(stored, client_map(ctx, prefix))
  end

  defp read_subtree_route({pattern, module, adapter_opts}, ctx, prefix, opts) do
    result =
      try do
        module.get_map(ctx, prefix, merge_opts(adapter_opts, opts))
      rescue
        reason ->
          Logger.warning(
            "Backpex.Preferences: adapter #{inspect(module)} raised in get_map/3 for prefix " <>
              "#{inspect(prefix)}: #{Exception.format(:error, reason, __STACKTRACE__)}"
          )

          {:error, {:exception, reason}}
      end

    case result do
      {:ok, map} when is_map(map) ->
        map

      # See `get_from_adapter/4`: `:unidentified` on a read is a documented
      # "not found", not a failure — no warning.
      {:error, :unidentified} ->
        %{}

      {:error, reason} ->
        Logger.warning(
          "Backpex.Preferences: adapter #{inspect(module)} returned error on get_map/3 for prefix " <>
            "#{inspect(prefix)} while reading route #{inspect(pattern)}: #{inspect(reason)}; " <>
            "falling back to %{}"
        )

        %{}

      other ->
        Logger.warning(
          "Backpex.Preferences: adapter #{inspect(module)} returned an invalid get_map/3 response " <>
            "for prefix #{inspect(prefix)} while reading route #{inspect(pattern)}: #{inspect(other)}; " <>
            "falling back to %{}"
        )

        %{}
    end
  end

  defp merge_subtree_route(route_map, acc, prefix_segments, {pattern, _module, _adapter_opts}) do
    route_segments =
      case pattern do
        :default -> prefix_segments
        pattern -> Key.wildcard_prefix(pattern) || Key.parse(pattern)
      end

    relative_path = Enum.drop(route_segments, length(prefix_segments))

    case fetch_nested(route_map, relative_path) do
      {:ok, value} -> put_nested_value(acc, relative_path, value)
      :error -> delete_nested_value(acc, relative_path)
    end
  end

  defp fetch_nested(value, []), do: {:ok, value}

  defp fetch_nested(map, [segment | rest]) when is_map(map) do
    case Map.fetch(map, segment) do
      {:ok, value} -> fetch_nested(value, rest)
      :error -> :error
    end
  end

  defp fetch_nested(_value, _path), do: :error

  defp put_nested_value(_map, [], value) when is_map(value), do: value
  defp put_nested_value(map, [], _value), do: map
  defp put_nested_value(map, [segment], value), do: Map.put(map, segment, value)

  defp put_nested_value(map, [segment | rest], value) do
    nested = if is_map(Map.get(map, segment)), do: Map.get(map, segment), else: %{}
    Map.put(map, segment, put_nested_value(nested, rest, value))
  end

  defp delete_nested_value(_map, []), do: %{}
  defp delete_nested_value(map, [segment]), do: Map.delete(map, segment)

  defp delete_nested_value(map, [segment | rest]) do
    case Map.get(map, segment) do
      nested when is_map(nested) ->
        updated = delete_nested_value(nested, rest)
        if updated == %{}, do: Map.delete(map, segment), else: Map.put(map, segment, updated)

      _other ->
        map
    end
  end

  # Client-supplied values (LiveView connect params) win over stored ones: they
  # are this tab's writes since websocket connect, which the connect-time
  # session snapshot cannot see. See `Backpex.Preferences.Context.put_client/2`.
  defp client_fetch(%Context{client: client}, key) when is_map(client), do: Map.fetch(client, key)
  defp client_fetch(_ctx_or_session, _key), do: :error

  # The `get_map/3` counterpart: every client key under `prefix`, keyed by the
  # segments that follow it, so it merges cleanly over the adapter's map.
  defp client_map(%Context{client: client}, prefix) when is_map(client) do
    scope = prefix <> "."

    client
    |> Enum.filter(fn {key, _value} -> String.starts_with?(key, scope) end)
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      path =
        key
        |> String.replace_prefix(scope, "")
        |> String.split(".")

      put_nested_value(acc, path, value)
    end)
  end

  defp client_map(_ctx_or_session, _prefix), do: %{}

  @doc """
  Persists a preference from within a LiveView socket or Plug controller.

  Resolves the adapter for `key`, asks it to persist the value, and applies
  the side effect it returns (e.g. `put_session`) to the caller. An adapter
  that persisted on its own returns `{:ok, :persisted}` and the caller is
  handed back unchanged.

  When the chosen adapter refuses a non-HTTP write with `:requires_http`
  (default behavior of the Session adapter outside a controller), falls back
  to `push_event/3` so the browser can retry via the preferences controller
  on its next paint.

  A socket target supplies `socket.assigns` but no mount session to the
  adapter/identity context (`ctx.session` is `%{}`). Identity resolution for
  server-originated LiveView writes must therefore work from assigns. A conn
  target supplies both `conn.assigns` and the current session.

  Returns one of:

    * `{:ok, socket_or_conn}` — write accepted.
    * `{:error, reason}` — the adapter refused the write for a non-transport
      reason. Callers typically ignore the failure (preferences are best
      effort) but can surface it if needed.

  ## Options

    * `:mirror` — `:session` to have the browser mirror the value into
      `sessionStorage`. Only consulted on the `push_event` fallback: it is a
      property of that round-trip, not of the value, and an adapter that
      persists server-side is read fresh at every mount and needs no mirror.
      See `Backpex.Preferences.LiveView.push_write/4` for when a key needs it.

  Every other option is forwarded to the adapter, on top of the adapter's
  configured options.

  ## Examples

  From a Plug controller (session is updated in-place):

      Backpex.Preferences.put(conn, "global.theme", "dark")
      #=> {:ok, %Plug.Conn{}}

  From a LiveView `handle_event` (session adapter returns `:requires_http`,
  so the dispatcher falls back to a `push_event` for the browser to retry):

      Backpex.Preferences.put(socket, "global.theme", "dark")
      #=> {:ok, %Phoenix.LiveView.Socket{}}
  """
  def put(target, key, value, opts \\ [])

  def put(%Plug.Conn{} = conn, key, value, opts) do
    ctx = conn |> Context.from_conn() |> resolve_identity()

    case dispatch_put(ctx, key, value, opts) do
      {_module, {:ok, :persisted}} ->
        {:ok, conn}

      {_module, {:ok, {:put_session, _session_key, _value} = effect}} ->
        {:ok, apply_effects_on_conn(conn, [effect])}

      {module, {:error, reason} = err} ->
        Logger.warning(
          "Backpex.Preferences: adapter #{inspect(module)} refused put/4 for key " <>
            "#{inspect(key)} on conn origin: #{inspect(reason)}"
        )

        err
    end
  end

  def put(%Socket{} = socket, key, value, opts) do
    ctx =
      %{}
      |> Context.from_socket(socket.assigns)
      |> resolve_identity()

    case dispatch_put(ctx, key, value, opts) do
      {_module, {:ok, :persisted}} ->
        {:ok, socket}

      # Trust boundary. `{:put_session, _, _}` cannot be applied to a live
      # socket — `Plug.Session` is HTTP-only. The Session adapter avoids
      # emitting it from a socket by returning `:requires_http` upstream, but a
      # third-party adapter can still get this wrong. Rather than crashing the
      # live render or silently dropping the write, warn and route through the
      # same push_event fallback so the write still lands.
      {module, {:ok, {:put_session, _session_key, _value}}} ->
        Logger.warning(
          "Backpex.Preferences: adapter #{inspect(module)} emitted {:put_session, _, _} from a " <>
            "socket origin for key #{inspect(key)}; routing through push_event fallback. " <>
            "Adapters should return :requires_http instead when called outside a controller."
        )

        {:ok, push_event_fallback(socket, key, value, opts)}

      {_module, {:error, :requires_http}} ->
        {:ok, push_event_fallback(socket, key, value, opts)}

      {module, {:error, reason} = err} ->
        Logger.warning(
          "Backpex.Preferences: adapter #{inspect(module)} refused put/4 for key " <>
            "#{inspect(key)} on socket origin: #{inspect(reason)}"
        )

        err
    end
  end

  @doc """
  Dispatches a batch of writes through their adapters and returns the
  collected side effects, or the first error encountered.

  Used by `Backpex.PreferencesController` to dispatch cross-adapter batch
  writes.

  Each entry's adapter returns at most one side effect, so the returned list
  holds one entry per write that needs the caller to do something — adapters
  that persisted on their own (`{:ok, :persisted}`) contribute nothing.

  Threads the accumulated session state through each adapter call so that
  writes under the same session key compose correctly. The caller applies
  the returned effects in order; for `:put_session` effects targeting the
  same key, the last effect holds the fully-merged value.

  ## Semantics

  This is **best-effort, first-error-wins**. On the first adapter that
  returns `{:error, reason}` the loop halts and returns
  `{:error, {key, reason}}` — subsequent entries are not dispatched. Earlier
  successful writes may already have been committed by their adapters (e.g.
  a DB-backed adapter that writes eagerly). The adapter behaviour has no
  rollback primitive, so callers should treat partial success as possible.

  ## Examples

      ctx = Backpex.Preferences.Context.from_conn(conn)

      Backpex.Preferences.put_batch(ctx, [
        {"global.theme", "dark"},
        {"global.sidebar_open", false}
      ])
      #=> {:ok, [{:put_session, "backpex_preferences", %{...}}]}
  """
  def put_batch(%Context{} = ctx, entries, opts \\ []) when is_list(entries) do
    ctx = resolve_identity(ctx)

    # Accumulate effects by prepending each adapter's effects in reverse, then
    # reverse the whole list at the end — preserves the original left-to-right
    # order while staying O(n) in batch size.
    result =
      Enum.reduce_while(entries, {[], ctx}, fn {key, value}, {reversed_acc, current_ctx} ->
        {_module, result} = dispatch_put(current_ctx, key, value, opts)

        case result do
          {:ok, :persisted} ->
            {:cont, {reversed_acc, current_ctx}}

          {:ok, {:put_session, _session_key, _value} = effect} ->
            {:cont, {[effect | reversed_acc], apply_effect_to_ctx(current_ctx, effect)}}

          {:error, reason} ->
            {:halt, {:error, {key, reason}}}
        end
      end)

    case result do
      {:error, _reason} = err -> err
      {reversed_acc, _ctx} -> {:ok, Enum.reverse(reversed_acc)}
    end
  end

  defp apply_effect_to_ctx(%Context{session: session} = ctx, {:put_session, key, value}) do
    %{ctx | session: Map.put(session, key, value)}
  end

  @doc """
  Applies a list of adapter side effects to a `%Plug.Conn{}`.

  Takes a list because a batch write collects one effect per entry (see
  `put_batch/3`); a single `put/4` yields at most one.

  Exposed for the preferences controller; not intended for general callers.
  """
  def apply_effects_on_conn(%Plug.Conn{} = conn, effects) when is_list(effects) do
    Enum.reduce(effects, conn, fn {:put_session, k, v}, c -> Plug.Conn.put_session(c, k, v) end)
  end

  @doc false
  def resolve_identity(%Context{identity: nil} = ctx) do
    identity = run_identity_resolver(ctx)
    Context.put_identity(ctx, identity)
  end

  def resolve_identity(%Context{} = ctx), do: ctx

  @doc """
  Returns the Phoenix session key used by the Session adapter.

  Convenience passthrough to `Backpex.Preferences.Adapters.Session.session_key/0`.
  """
  def session_key, do: Adapters.Session.session_key()

  defp dispatch_get(ctx_or_session, key, opts) do
    ctx = resolve_identity(Context.coerce(ctx_or_session))
    {module, adapter_opts} = Router.resolve(key)

    try do
      {module, module.get(ctx, key, merge_opts(adapter_opts, opts))}
    rescue
      reason ->
        Logger.warning(
          "Backpex.Preferences: adapter #{inspect(module)} raised in get/3 for key " <>
            "#{inspect(key)}: #{Exception.format(:error, reason, __STACKTRACE__)}"
        )

        {module, {:error, {:exception, reason}}}
    end
  end

  # Every write — HTTP endpoint, LiveView, host app — funnels through here, so
  # this is where a value that a built-in reader provably cannot consume gets
  # refused. Without it a single wrong-typed write persists and then raises on
  # every later render (`not "false"`, `Map.get/3` on a binary), 500ing every
  # admin page for the life of that user's session with no way to reach a page
  # to undo it. `Context.put_client/2` already applies the same gate to the
  # ephemeral overlay; the durable path must not be the weaker of the two.
  #
  # This is a shape gate, not authorization: keys Backpex does not own
  # (`custom.*`, unknown `resource:` suffixes) pass through untouched, so it
  # costs host apps no flexibility.
  defp dispatch_put(%Context{} = ctx, key, value, opts) do
    {module, adapter_opts} = Router.resolve(key)

    if Keys.valid_value?(key, value) do
      dispatch_put_to_adapter(module, adapter_opts, ctx, key, value, opts)
    else
      Logger.warning(
        "Backpex.Preferences: refusing put/4 for key #{inspect(key)}: #{inspect(value)} is not a " <>
          "shape the built-in reader for this key can consume. Storing it would raise on later renders."
      )

      {module, {:error, :invalid_value}}
    end
  end

  defp dispatch_put_to_adapter(module, adapter_opts, ctx, key, value, opts) do
    {module, module.put(ctx, key, value, merge_opts(adapter_opts, opts))}
  rescue
    reason ->
      Logger.warning(
        "Backpex.Preferences: adapter #{inspect(module)} raised in put/4 for key " <>
          "#{inspect(key)}: #{Exception.format(:error, reason, __STACKTRACE__)}"
      )

      {module, {:error, {:exception, reason}}}
  end

  defp push_event_fallback(socket, key, value, opts) do
    PreferenceLiveView.push_write(socket, key, value, Keyword.take(opts, [:mirror]))
  end

  # `:default` (read fallback) and `:mirror` (a property of the push_event
  # round-trip) are the dispatcher's own options. An adapter never acts on
  # either, so they stop here rather than leaking into the adapter contract.
  defp merge_opts(adapter_opts, call_opts) do
    Keyword.merge(adapter_opts, Keyword.drop(call_opts, [:default, :mirror]))
  end

  defp run_identity_resolver(ctx) do
    case Application.get_env(:backpex, __MODULE__, [])[:identity] do
      {mod, fun, args} when is_atom(mod) and is_atom(fun) and is_list(args) ->
        safe_apply(mod, fun, [ctx | args])

      nil ->
        :unidentified

      other ->
        Logger.warning(
          "Backpex.Preferences: invalid :identity config #{inspect(other)}; " <>
            "expected {module, function, args} or nil; falling back to :unidentified"
        )

        :unidentified
    end
  end

  defp safe_apply(mod, fun, args) do
    normalize_identity(apply(mod, fun, args))
  rescue
    reason ->
      Logger.warning(
        "Backpex.Preferences: resolving identity via #{inspect({mod, fun, length(args)})} raised: " <>
          "#{Exception.format(:error, reason, __STACKTRACE__)}; falling back to :unidentified"
      )

      :unidentified
  catch
    kind, reason ->
      Logger.warning(
        "Backpex.Preferences: resolving identity via #{inspect({mod, fun, length(args)})} " <>
          "threw #{inspect(kind)}: #{inspect(reason)}; falling back to :unidentified"
      )

      :unidentified
  end

  defp normalize_identity({:ok, nil}), do: :unidentified
  defp normalize_identity({:ok, id}), do: id
  defp normalize_identity(:unidentified), do: :unidentified
  defp normalize_identity(:error), do: :unidentified
  defp normalize_identity({:error, _reason}), do: :unidentified
  defp normalize_identity(nil), do: :unidentified
  defp normalize_identity(id), do: id
end
