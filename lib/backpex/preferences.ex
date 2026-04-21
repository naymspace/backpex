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
    * `fetch/3` — read a single preference and distinguish missing values
      (`:error`) from adapter errors (`{:error, reason}`).
    * `get_map/3` — read every value under a prefix as a nested map.
    * `put/4` — write from a LiveView socket or `%Plug.Conn{}`.
    * `put_batch/3` — dispatch a list of writes (best-effort, first-error-wins;
      see the function docs for the partial-success semantics).

  ### `get/3` vs `fetch/3`

  `get/3` is the common case: you want a value, falling back to a default
  when there is no stored value for any reason (user hasn't set one, no user
  is identified yet, adapter transiently failed).

  Reach for `fetch/3` when you need to tell "user has no preference yet"
  apart from "there's no user to read a preference for" — e.g. prompting an
  anonymous visitor to sign in to save their view:

      case Backpex.Preferences.fetch(session, "custom.dashboard.view_mode") do
        {:ok, mode} ->
          # User has deliberately chosen a view mode — use it.
          mode

        :error ->
          # Either no user is identified (anonymous visitor) or the logged-in
          # user hasn't set one. Show the default AND a "sign in to save your
          # view" CTA. `get/3` would have collapsed both into the default.
          "grid"

        {:error, _reason} ->
          # Adapter failure — already logged. Fall back silently.
          "grid"
      end
  """

  alias Backpex.Preferences.Adapters
  alias Backpex.Preferences.Context
  alias Backpex.Preferences.Key
  alias Backpex.Preferences.LiveView, as: PreferenceLiveView
  alias Backpex.Preferences.Router

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

  ## Examples

      iex> session = %{"backpex_preferences" => %{"global" => %{"theme" => "dark"}}}
      iex> Backpex.Preferences.get(session, "global.theme")
      "dark"

      iex> Backpex.Preferences.get(%{}, "global.theme", default: "light")
      "light"
  """
  @spec get(Context.t() | map(), String.t(), keyword()) :: term()
  def get(ctx_or_session, key, opts \\ []) do
    default = Keyword.get(opts, :default)

    case dispatch_get(ctx_or_session, key, opts) do
      {_module, {:ok, :not_found}} ->
        default

      {_module, {:ok, value}} ->
        value

      {module, {:error, reason}} ->
        Logger.warning(
          "Backpex.Preferences: adapter #{inspect(module)} returned error on get/3 for key " <>
            "#{inspect(key)}: #{inspect(reason)}; falling back to default"
        )

        default
    end
  end

  @doc """
  Reads a preference and returns a result tuple that distinguishes missing
  values from adapter failures.

  Unlike `get/3`, which collapses every non-success case to `opts[:default]`,
  this function gives callers enough signal to react differently.

  Use `fetch/3` when you need to distinguish "user hasn't set a preference
  yet" from "anonymous visitor / nothing to read" — for example, to show a
  "sign in to save your view" CTA, or to decide whether to apply a
  resource-level default. `get/3` collapses both to the `:default` option.

  Returns:

    * `{:ok, value}` — the adapter returned a stored value.
    * `:error` — the adapter successfully determined nothing is stored
      (`{:ok, :not_found}` from the adapter), **or** the adapter returned
      `{:error, :unidentified}`. The `Backpex.Preferences.Adapter`
      behaviour defines `:unidentified` on reads as "treat as not found",
      so no warning is logged for that case — it is expected (anonymous
      visitors, background jobs, etc.).
    * `{:error, reason}` — any other adapter failure (e.g. a raised
      exception swallowed by the dispatcher). A warning is also logged.

  Note that `:error` cannot tell "no user identified" apart from "user has
  not set this preference yet" — both collapse to the same tag. What
  `fetch/3` does give you is a signal separate from *application* defaults:
  if your code needs to decide whether to apply a default based on whether
  the user has deliberately set a value (including to a semantically empty
  `%{}` or `[]`), match on `:error` vs `{:ok, _}` rather than inspecting the
  resolved value's shape.

  ## Examples

      iex> session = %{"backpex_preferences" => %{"global" => %{"theme" => "dark"}}}
      iex> Backpex.Preferences.fetch(session, "global.theme")
      {:ok, "dark"}

      iex> Backpex.Preferences.fetch(%{}, "global.theme")
      :error
  """
  @spec fetch(Context.t() | map(), String.t(), keyword()) ::
          {:ok, term()} | :error | {:error, term()}
  def fetch(ctx_or_session, key, opts \\ []) do
    case dispatch_get(ctx_or_session, key, opts) do
      {_module, {:ok, :not_found}} ->
        :error

      {_module, {:ok, value}} ->
        {:ok, value}

      {_module, {:error, :unidentified}} ->
        # The adapter behaviour defines `:unidentified` on reads as "treat as
        # not found" — collapse to `:error` without logging. This matches the
        # expected path for anonymous visitors / background jobs that have no
        # resolved identity.
        :error

      {module, {:error, reason} = err} ->
        Logger.warning(
          "Backpex.Preferences: adapter #{inspect(module)} returned error on fetch/3 for key " <>
            "#{inspect(key)}: #{inspect(reason)}"
        )

        err
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
  @spec get_map(Context.t() | map(), String.t(), keyword()) :: map()
  def get_map(ctx_or_session, prefix, opts \\ []) do
    ctx = resolve_identity(Context.coerce(ctx_or_session))
    {module, adapter_opts} = Router.resolve_prefix(prefix)

    case module.get_map(ctx, prefix, merge_opts(adapter_opts, opts)) do
      {:ok, map} when is_map(map) ->
        map

      {:error, reason} ->
        Logger.warning(
          "Backpex.Preferences: adapter #{inspect(module)} returned error on get_map/3 for prefix " <>
            "#{inspect(prefix)}: #{inspect(reason)}; falling back to %{}"
        )

        %{}
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

  ## Examples

  From a Plug controller (session is updated in-place):

      Backpex.Preferences.put(conn, "global.theme", "dark")
      #=> {:ok, %Plug.Conn{}}

  From a LiveView `handle_event` (session adapter returns `:requires_http`,
  so the dispatcher falls back to a `push_event` for the browser to retry):

      Backpex.Preferences.put(socket, "global.theme", "dark")
      #=> {:ok, %Phoenix.LiveView.Socket{}}
  """
  @spec put(Plug.Conn.t() | Phoenix.LiveView.Socket.t(), String.t(), term(), keyword()) ::
          {:ok, Plug.Conn.t() | Phoenix.LiveView.Socket.t()} | {:error, term()}
  def put(target, key, value, opts \\ [])

  def put(%Plug.Conn{} = conn, key, value, opts) do
    ctx = conn |> Context.from_conn() |> resolve_identity()

    case dispatch_put(ctx, key, value, opts) do
      {_module, {:ok, effects}} ->
        {:ok, apply_effects_on_conn(conn, effects)}

      {module, {:error, reason} = err} ->
        Logger.warning(
          "Backpex.Preferences: adapter #{inspect(module)} refused put/4 for key " <>
            "#{inspect(key)} on conn origin: #{inspect(reason)}"
        )

        err
    end
  end

  def put(%Phoenix.LiveView.Socket{} = socket, key, value, opts) do
    ctx =
      %{}
      |> Context.from_socket(socket.assigns)
      |> resolve_identity()

    case dispatch_put(ctx, key, value, opts) do
      {module, {:ok, effects}} ->
        {:ok, apply_effects_on_socket(socket, module, key, value, effects)}

      {_module, {:error, :requires_http}} ->
        {:ok, push_event_fallback(socket, key, value)}

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
  @spec put_batch(Context.t(), [{String.t(), term()}], keyword()) ::
          {:ok, [Backpex.Preferences.Adapter.side_effect()]} | {:error, {String.t(), term()}}
  def put_batch(%Context{} = ctx, entries, opts \\ []) when is_list(entries) do
    ctx = resolve_identity(ctx)

    # Accumulate effects by prepending each adapter's effects in reverse, then
    # reverse the whole list at the end — preserves the original left-to-right
    # order while staying O(n) in batch size.
    result =
      Enum.reduce_while(entries, {[], ctx}, fn {key, value}, {reversed_acc, current_ctx} ->
        {module, adapter_opts} = Router.resolve(key)

        case module.put(current_ctx, key, value, merge_opts(adapter_opts, opts)) do
          {:ok, fx} ->
            {:cont, {:lists.reverse(fx, reversed_acc), apply_effects_to_ctx(current_ctx, fx)}}

          {:error, reason} ->
            {:halt, {:error, {key, reason}}}
        end
      end)

    case result do
      {:error, _reason} = err -> err
      {reversed_acc, _ctx} -> {:ok, Enum.reverse(reversed_acc)}
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
  Returns the Phoenix session key used by the Session adapter.

  Convenience passthrough to `Backpex.Preferences.Adapters.Session.session_key/0`.
  """
  @spec session_key() :: String.t()
  def session_key, do: Adapters.Session.session_key()

  @doc """
  Splits a preference key into path segments.

  Convenience passthrough to `Backpex.Preferences.Key.parse/1`.
  """
  @spec parse_key(String.t()) :: [String.t()]
  def parse_key(key), do: Key.parse(key)

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

  defp dispatch_put(%Context{} = ctx, key, value, opts) do
    {module, adapter_opts} = Router.resolve(key)

    try do
      {module, module.put(ctx, key, value, merge_opts(adapter_opts, opts))}
    rescue
      reason ->
        Logger.warning(
          "Backpex.Preferences: adapter #{inspect(module)} raised in put/4 for key " <>
            "#{inspect(key)}: #{Exception.format(:error, reason, __STACKTRACE__)}"
        )

        {module, {:error, {:exception, reason}}}
    end
  end

  # Socket-origin put accepted by the adapter: consume the returned side
  # effects. `:noop` is the common case (DB-backed adapters that persisted
  # themselves). `{:put_session, _, _}` cannot be applied to a live socket
  # — `Plug.Session` is HTTP-only. The Session adapter avoids emitting this
  # from a socket by returning `:requires_http` upstream, but a third-party
  # adapter could still emit it. Rather than silently dropping the write,
  # log a warning and fall back to `push_event/3` so the browser can retry
  # via the preferences controller.
  defp apply_effects_on_socket(socket, module, key, value, effects) do
    Enum.reduce(effects, socket, fn
      :noop, s ->
        s

      {:put_session, _k, _v}, s ->
        Logger.warning(
          "Backpex.Preferences: adapter #{inspect(module)} emitted {:put_session, _, _} from a " <>
            "socket origin for key #{inspect(key)}; routing through push_event fallback. " <>
            "Adapters should return :requires_http instead when called outside a controller."
        )

        push_event_fallback(s, key, value)
    end)
  end

  defp push_event_fallback(socket, key, value) do
    PreferenceLiveView.push_write(socket, key, value)
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
