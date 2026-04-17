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
  `Backpex.Preferences.Adapters.Session` — matches the legacy single-adapter
  behavior.

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

    * `get/3` — read a single preference.
    * `get_map/3` — read every value under a prefix as a nested map.
    * `put_async/4` — write from a LiveView socket or `%Plug.Conn{}`.
  """

  alias Backpex.Preferences.Adapters
  alias Backpex.Preferences.Context
  alias Backpex.Preferences.Key
  alias Backpex.Preferences.Router

  @doc """
  Reads a preference. Falls back to `opts[:default]` when the value is
  missing or the adapter cannot identify the current user.

  Accepts a `%Backpex.Preferences.Context{}` or a bare Phoenix session map —
  the session-map form is kept for backward compatibility with the legacy
  `Preferences.get(session, key)` call sites.

  ## Options

    * `:default` — returned when nothing is stored for `key` (default: `nil`).

  Extra options are forwarded to the adapter.
  """
  @spec get(Context.t() | map(), String.t(), keyword()) :: term()
  def get(ctx_or_session, key, opts \\ []) do
    default = Keyword.get(opts, :default)

    case dispatch_get(ctx_or_session, key, opts) do
      {:ok, :not_found} -> default
      {:ok, value} -> value
      {:error, _reason} -> default
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
  """
  @spec get_map(Context.t() | map(), String.t(), keyword()) :: map()
  def get_map(ctx_or_session, prefix, opts \\ []) do
    ctx = resolve_identity(Context.coerce(ctx_or_session))
    {module, adapter_opts} = Router.resolve(prefix)

    case module.get_map(ctx, prefix, merge_opts(adapter_opts, opts)) do
      {:ok, map} when is_map(map) -> map
      {:error, _reason} -> %{}
    end
  end

  @doc """
  Persists a preference from within a LiveView socket or Plug controller.

  Resolves the adapter for `key`, asks it to persist the value, and applies
  the returned side effects (e.g. `put_session`) to the caller.

  When the chosen adapter refuses a non-HTTP write with `:requires_http`
  (default behavior of the Session adapter outside a controller), falls back
  to `push_event/3` so the browser can retry via the preferences controller
  on its next paint.

  Returns one of:

    * `{:ok, socket_or_conn}` — write accepted.
    * `{:error, reason}` — the adapter refused the write for a non-transport
      reason. Callers typically ignore the failure (preferences are best
      effort) but can surface it if needed.
  """
  @spec put_async(Plug.Conn.t() | Phoenix.LiveView.Socket.t(), String.t(), term(), keyword()) ::
          {:ok, Plug.Conn.t() | Phoenix.LiveView.Socket.t()} | {:error, term()}
  def put_async(target, key, value, opts \\ [])

  def put_async(%Plug.Conn{} = conn, key, value, opts) do
    ctx = conn |> Context.from_conn() |> resolve_identity()

    case dispatch_put(ctx, key, value, opts) do
      {:ok, effects} -> {:ok, apply_effects_on_conn(conn, effects)}
      {:error, _reason} = err -> err
    end
  end

  def put_async(%Phoenix.LiveView.Socket{} = socket, key, value, opts) do
    ctx =
      %{}
      |> Context.from_socket(socket.assigns)
      |> resolve_identity()

    case dispatch_put(ctx, key, value, opts) do
      {:ok, effects} -> {:ok, apply_effects_on_socket(socket, effects)}
      {:error, :requires_http} -> {:ok, push_event_fallback(socket, key, value)}
      {:error, _reason} = err -> err
    end
  end

  @doc """
  Dispatches a batch of writes through their adapters and returns the
  collected side effects, or an error list (all-or-nothing).

  Used by `Backpex.PreferencesController` to implement cross-adapter batch
  writes with a clean failure mode.

  Threads the accumulated session state through each adapter call so that
  writes under the same session key compose correctly. The caller applies
  the returned effects in order; for `:put_session` effects targeting the
  same key, the last effect holds the fully-merged value.
  """
  @spec put_batch(Context.t(), [{String.t(), term()}], keyword()) ::
          {:ok, [Backpex.Preferences.Adapter.side_effect()]} | {:error, [term()]}
  def put_batch(%Context{} = ctx, entries, opts \\ []) when is_list(entries) do
    ctx = resolve_identity(ctx)

    {effects, errors, _final_ctx} =
      Enum.reduce(entries, {[], [], ctx}, fn {key, value}, {effects_acc, errors_acc, current_ctx} ->
        {module, adapter_opts} = Router.resolve(key)

        case module.put(current_ctx, key, value, merge_opts(adapter_opts, opts)) do
          {:ok, fx} ->
            {effects_acc ++ fx, errors_acc, apply_effects_to_ctx(current_ctx, fx)}

          {:error, reason} ->
            {effects_acc, [{key, reason} | errors_acc], current_ctx}
        end
      end)

    case errors do
      [] -> {:ok, effects}
      errs -> {:error, Enum.reverse(errs)}
    end
  end

  defp apply_effects_to_ctx(%Context{} = ctx, effects) do
    session =
      Enum.reduce(effects, ctx.session, fn
        {:put_session, key, value}, sess -> Map.put(sess, key, value)
        :noop, sess -> sess
      end)

    %{ctx | session: session}
  end

  @doc """
  Applies a list of adapter side effects to a `%Plug.Conn{}`.

  Exposed for the preferences controller; not intended for general callers.
  """
  @spec apply_effects_on_conn(Plug.Conn.t(), [Backpex.Preferences.Adapter.side_effect()]) :: Plug.Conn.t()
  def apply_effects_on_conn(%Plug.Conn{} = conn, effects) when is_list(effects) do
    Enum.reduce(effects, conn, fn
      {:put_session, k, v}, c -> Plug.Conn.put_session(c, k, v)
      :noop, c -> c
    end)
  end

  @doc false
  def resolve_identity(%Context{identity: nil} = ctx) do
    identity = run_identity_resolver(ctx)
    Context.put_identity(ctx, identity)
  end

  def resolve_identity(%Context{} = ctx), do: ctx

  @doc """
  Legacy alias preserved for call sites that still reference the Phoenix
  session key directly. New code should read
  `Backpex.Preferences.Adapters.Session.session_key/0`.
  """
  @spec session_key() :: String.t()
  def session_key, do: Adapters.Session.session_key()

  @doc """
  Legacy alias for `Backpex.Preferences.Key.parse/1`.
  """
  @spec parse_key(String.t()) :: [String.t()]
  def parse_key(key), do: Key.parse(key)

  defp dispatch_get(ctx_or_session, key, opts) do
    ctx = resolve_identity(Context.coerce(ctx_or_session))
    {module, adapter_opts} = Router.resolve(key)
    module.get(ctx, key, merge_opts(adapter_opts, opts))
  end

  defp dispatch_put(%Context{} = ctx, key, value, opts) do
    {module, adapter_opts} = Router.resolve(key)
    module.put(ctx, key, value, merge_opts(adapter_opts, opts))
  end

  defp apply_effects_on_socket(socket, effects) do
    Enum.reduce(effects, socket, fn
      :noop, s -> s
      {:put_session, _k, _v}, s -> s
    end)
  end

  defp push_event_fallback(socket, key, value) do
    Phoenix.LiveView.push_event(socket, "backpex:set_preference", %{key: key, value: value})
  end

  defp merge_opts(adapter_opts, call_opts) do
    Keyword.merge(adapter_opts, Keyword.delete(call_opts, :default))
  end

  defp run_identity_resolver(ctx) do
    case Application.get_env(:backpex, __MODULE__, [])[:identity] do
      {mod, fun, args} when is_atom(mod) and is_atom(fun) and is_list(args) ->
        safe_apply(mod, fun, [ctx | args])

      nil ->
        :unidentified
    end
  end

  defp safe_apply(mod, fun, args) do
    normalize_identity(apply(mod, fun, args))
  rescue
    _reason -> :unidentified
  catch
    _kind, _reason -> :unidentified
  end

  defp normalize_identity({:ok, nil}), do: :unidentified
  defp normalize_identity({:ok, id}), do: id
  defp normalize_identity(:unidentified), do: :unidentified
  defp normalize_identity(:error), do: :unidentified
  defp normalize_identity({:error, _reason}), do: :unidentified
  defp normalize_identity(nil), do: :unidentified
  defp normalize_identity(id), do: id
end
