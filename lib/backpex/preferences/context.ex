defmodule Backpex.Preferences.Context do
  @moduledoc """
  Runtime context passed to `Backpex.Preferences.Adapter` callbacks.

  A context captures where a preference read/write originated and gives
  adapters the handles they need (session, assigns, scope) without
  forcing every adapter to know about `Plug.Conn` or LiveView socket
  internals.

  Populate via one of the builders:

  - `from_mount/2` — LiveView mount / on_mount hook (read path).
  - `from_conn/1` — Plug controller (write path over HTTP).
  - `from_socket/2` — server-side preference writes from a LiveView.
  - `coerce/1` — wraps a bare session map so callers that only have a
    session on hand can still use the dispatcher.

  ## The `scope` field

  `scope` holds the preference namespace returned by the configured scope
  resolver (see `Backpex.Preferences`). A resolved scope is a non-empty,
  atom-keyed map, for example `%{user_id: user.id, tenant_id: tenant.id}`. It is `nil` before
  the dispatcher runs resolution and `:unscoped` when the resolver could not
  determine a namespace.

  Resolution runs once for each unresolved context. Reusing a context whose
  `scope` is already populated reuses the resolved scope. Entry points that
  receive a bare session, conn, or socket build a fresh context and therefore
  run the resolver again. Keep the resolver cheap.
  """

  alias __MODULE__

  @type source :: :mount | :controller | :server
  @type scope :: %{required(atom()) => term()} | :unscoped | nil

  @type t :: %__MODULE__{
          source: source(),
          session: map(),
          assigns: map(),
          scope: scope(),
          client: %{optional(String.t()) => term()}
        }

  defstruct source: :mount, session: %{}, assigns: %{}, scope: nil, client: %{}

  @doc """
  Build a context for a read originating at LiveView mount.

  `assigns` defaults to `%{}` for callers that only have a session on hand.
  """
  def from_mount(session, assigns \\ %{}) when is_map(session) and is_map(assigns) do
    %Context{source: :mount, session: session, assigns: assigns}
  end

  @doc """
  Overlay client-supplied preference values on a context.

  Reads through `Backpex.Preferences.get/3` and `get_map/3` prefer these
  values over whatever the adapter has stored. They reach the server on
  two carriers, both described in `Backpex.Preferences.LiveView`: the connect
  params of every websocket join (which carry the writes a tab made *after* it
  connected — writes the frozen connect-time session cannot see on a
  `live_redirect` re-mount), and the `backpex_prefs` cookie (which carries the
  writes the server has not acknowledged yet, so the disconnected mount can
  render them before the write's POST has even landed).

  Both payloads are written by the browser, so both are untrusted and are
  filtered here:

    * keys that fail `Backpex.Preferences.Key.validate/1` are dropped — an
      unknown key would otherwise shadow a read for a prefix no adapter is
      configured to serve;
    * values that fail `Backpex.Preferences.Keys.valid_value?/2` are dropped —
      a wrong-typed value for a built-in key would otherwise reach a render,
      and a render must not raise on browser input (`not "false"` does).

  Neither check is an authorization gate: a client may already write any value
  it likes through the preferences endpoint. They exist so a planted or
  truncated payload degrades to the stored value instead of taking the page
  down. Values for keys Backpex does not own pass through unchecked — see
  `Backpex.Preferences.Keys.valid_value?/2`.

  ## Examples

      iex> alias Backpex.Preferences.Context
      iex> ctx = Context.put_client(Context.from_mount(%{}), %{"global.theme" => "dark", "bogus.key" => 1})
      iex> ctx.client
      %{"global.theme" => "dark"}

      iex> alias Backpex.Preferences.Context
      iex> ctx = Context.put_client(Context.from_mount(%{}), %{"global.sidebar_open" => "false"})
      iex> ctx.client
      %{}

      iex> alias Backpex.Preferences.Context
      iex> ctx = Context.put_client(Context.from_mount(%{}), %{"global.sidebar_open" => false})
      iex> ctx.client
      %{"global.sidebar_open" => false}
  """
  def put_client(%Context{} = ctx, client) when is_map(client) do
    %{ctx | client: Map.filter(client, fn {key, value} -> valid_client_entry?(key, value) end)}
  end

  def put_client(%Context{} = ctx, _client), do: %{ctx | client: %{}}

  defp valid_client_entry?(key, value) when is_binary(key) do
    Backpex.Preferences.Key.validate(key) == :ok and Backpex.Preferences.Keys.valid_value?(key, value)
  end

  defp valid_client_entry?(_key, _value), do: false

  @doc """
  Build a context from a `%Plug.Conn{}` (write path over HTTP).

  Extracts the session and assigns from the conn and discards the conn
  itself — adapters receive the extracted values and never see the `conn`
  directly, which keeps adapter code free of a `Plug.Conn` dependency.
  """
  def from_conn(%Plug.Conn{} = conn) do
    %Context{
      source: :controller,
      session: Plug.Conn.get_session(conn),
      assigns: conn.assigns
    }
  end

  @doc """
  Build a context for a server-originated preference write from within a
  LiveView (e.g. a `handle_event` that already knows the new value).
  """
  def from_socket(session, assigns) when is_map(session) and is_map(assigns) do
    %Context{source: :server, session: session, assigns: assigns}
  end

  @doc """
  Wrap a bare session map (or pass through an existing context) so call
  sites that only have a session map can still call `Preferences.get/3` and
  friends.

  Accepts:

    * `%Backpex.Preferences.Context{}` — passed through unchanged.
    * A plain Phoenix session map (non-struct map with string keys, or the
      empty map `%{}`) — wrapped via `from_mount/1`.

  Raises `ArgumentError` on any other shape. In particular, arbitrary maps
  with atom keys, structs (other than `Context`), or non-map terms are
  rejected rather than silently wrapped — wrapping them would mask caller
  bugs and route a nonsense context into the adapter layer.
  """
  def coerce(%Context{} = ctx), do: ctx

  def coerce(session) when is_map(session) and not is_struct(session) do
    if session_shaped?(session) do
      from_mount(session)
    else
      raise ArgumentError,
            "Backpex.Preferences.Context.coerce/1 expected a %Context{} or a Phoenix " <>
              "session map (string-keyed), got: " <>
              inspect(session)
    end
  end

  def coerce(other) do
    raise ArgumentError,
          "Backpex.Preferences.Context.coerce/1 expected a %Context{} or a Phoenix " <>
            "session map, got: " <>
            inspect(other)
  end

  # Session maps are always string-keyed (Plug.Session stores them that way).
  # Accept the empty map as a degenerate session, but reject atom-keyed or
  # mixed-key maps to catch accidental caller mistakes.
  defp session_shaped?(map) when map_size(map) == 0, do: true

  defp session_shaped?(map) do
    map
    |> Map.keys()
    |> Enum.all?(&is_binary/1)
  end

  @doc """
  Returns `%{ctx | scope: scope}`.

  Called after the configured scope resolver runs. Adapter callbacks receive
  the already-resolved scope, and subsequent dispatches that reuse this context
  do not run the resolver again.
  """
  def put_scope(%Context{} = ctx, scope), do: %{ctx | scope: scope}
end
