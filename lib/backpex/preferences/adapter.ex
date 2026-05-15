defmodule Backpex.Preferences.Adapter do
  @moduledoc """
  Behavior implemented by Backpex preference storage adapters.

  `Backpex.Preferences` dispatches each call to an adapter selected by the
  key's prefix. Ship with `Backpex.Preferences.Adapters.Session` by default and
  configure others per prefix:

      config :backpex, Backpex.Preferences,
        adapters: [
          {"global.*",   Backpex.Preferences.Adapters.Session, []},
          {"resource.*", MyApp.Preferences.EctoAdapter, repo: MyApp.Repo},
          {:default,     Backpex.Preferences.Adapters.Session, []}
        ]

  ## Return semantics

  The three atoms in the return types deserve a note:

  - `{:ok, :not_found}` — the adapter successfully determined that no value is
    stored for this key. `Backpex.Preferences.get/3` callers fall back to
    their `:default` option.
  - `{:error, :unidentified}` — the adapter needs a resolved user (see
    `Backpex.Preferences.Context.identity`) and does not have one. Reads
    should be treated as "not found"; writes surface `{ok: false}` to the
    caller without crashing.
  - `{:error, :requires_http}` — the adapter can only write via a
    `%Plug.Conn{}` (e.g. the Session adapter writing to the session cookie)
    and was invoked from a context that has no conn (mount / socket). The
    server-side helper in `Backpex.Preferences` catches this and falls back to
    a `push_event/3` round-trip so the browser can retry via the HTTP
    endpoint.

  ## Side-effect protocol

  Writes return a list of side effects rather than mutating the conn. The
  dispatcher/controller applies each side effect in the order it was returned.

  The `:put_session` effect asks the caller to put a map under the given
  session key. `:noop` is useful for adapters that fully persisted the value
  themselves (e.g. database writes).

  Keeping adapters side-effect-free this way lets them be exercised in unit
  tests without a conn and supports server-side writes that do not have one.
  """

  alias Backpex.Preferences.Context

  @typedoc """
  A side effect the caller is responsible for applying after `c:put/4`.
  """
  @type side_effect ::
          {:put_session, key :: String.t(), value :: map()}
          | :noop

  @doc """
  Read a single key.

  Return `{:ok, :not_found}` when no value is stored; callers fall back to
  their `:default` option.
  """
  @callback get(ctx :: Context.t(), key :: String.t(), opts :: keyword()) ::
              {:ok, term()} | {:ok, :not_found} | {:error, :unidentified | term()}

  @doc """
  Read every value under `prefix` and return them as a nested map.

  The returned map mirrors the structure that a `get/3` at that prefix would
  have produced if there were a single nested value — i.e. it is keyed by the
  path segments that come after `prefix`, not by full dotted/coloned keys.
  """
  @callback get_map(ctx :: Context.t(), prefix :: String.t(), opts :: keyword()) ::
              {:ok, map()} | {:error, :unidentified | term()}

  @doc """
  Persist a value.

  Return side effects for the caller to apply (see the module docs). When the
  adapter persists on its own (DB write), return `{:ok, [:noop]}`.
  """
  @callback put(ctx :: Context.t(), key :: String.t(), value :: term(), opts :: keyword()) ::
              {:ok, [side_effect()]} | {:error, :unidentified | :requires_http | term()}
end
