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

  Return `{:ok, :persisted}` when the adapter stored the value itself (a DB
  write), or `{:ok, {:put_session, key, map}}` to ask the caller to apply the
  one side effect the adapter cannot perform on its own (see the module docs).
  """
  @callback put(ctx :: Context.t(), key :: String.t(), value :: term(), opts :: keyword()) ::
              {:ok, put_result()} | {:error, :unidentified | :requires_http | term()}
end
