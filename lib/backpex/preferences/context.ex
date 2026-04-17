defmodule Backpex.Preferences.Context do
  @moduledoc """
  Runtime context passed to `Backpex.Preferences.Adapter` callbacks.

  A context captures where a preference read/write originated and gives
  adapters the handles they need (session, conn, assigns) without forcing
  every adapter to know about `Plug.Conn` or LiveView socket internals.

  Populate via one of the builders:

  - `from_mount/2` — LiveView mount / on_mount hook (read path).
  - `from_conn/1` — Plug controller (write path over HTTP).
  - `from_socket/2` — server-side preference writes from a LiveView.
  - `coerce/1` — wraps a bare session map for backward compatibility with the
    legacy `Backpex.Preferences.get(session, key)` API.

  ## The `identity` field

  `identity` holds the current user's identifier as returned by the configured
  identity resolver (see `Backpex.Preferences`). It is `nil` before the
  dispatcher runs resolution, `:unidentified` when the resolver could not find
  a user, or any term the resolver returned on success (usually a user id).

  Adapters read `ctx.identity` and do not have to re-resolve per call.
  """

  alias __MODULE__

  @type source :: :mount | :controller | :server
  @type identity :: term() | :unidentified | nil

  @type t :: %__MODULE__{
          source: source(),
          session: map(),
          conn: Plug.Conn.t() | nil,
          assigns: map(),
          identity: identity()
        }

  defstruct source: :mount, session: %{}, conn: nil, assigns: %{}, identity: nil

  @doc """
  Build a context for a read originating at LiveView mount.

  `assigns` defaults to `%{}` for callers that only have a session (e.g. the
  legacy `Preferences.get(session, key)` path).
  """
  @spec from_mount(map(), map()) :: t()
  def from_mount(session, assigns \\ %{}) when is_map(session) and is_map(assigns) do
    %Context{source: :mount, session: session, assigns: assigns}
  end

  @doc """
  Build a context from a `%Plug.Conn{}` (write path over HTTP).
  """
  @spec from_conn(Plug.Conn.t()) :: t()
  def from_conn(%Plug.Conn{} = conn) do
    %Context{
      source: :controller,
      conn: conn,
      session: Plug.Conn.get_session(conn),
      assigns: conn.assigns
    }
  end

  @doc """
  Build a context for a server-originated preference write from within a
  LiveView (e.g. a `handle_event` that already knows the new value).
  """
  @spec from_socket(map(), map()) :: t()
  def from_socket(session, assigns) when is_map(session) and is_map(assigns) do
    %Context{source: :server, session: session, assigns: assigns}
  end

  @doc """
  Wrap a bare session map (or pass through an existing context) so the legacy
  `Preferences.get(session, key)` call sites keep working.
  """
  @spec coerce(t() | map()) :: t()
  def coerce(%Context{} = ctx), do: ctx
  def coerce(session) when is_map(session), do: from_mount(session)

  @doc """
  Returns `%{ctx | identity: identity}`.

  Called by the dispatcher once per context, after it runs the configured
  identity resolver; adapters receive the already-resolved value.
  """
  @spec put_identity(t(), identity()) :: t()
  def put_identity(%Context{} = ctx, identity), do: %{ctx | identity: identity}
end
