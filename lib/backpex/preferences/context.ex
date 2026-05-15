defmodule Backpex.Preferences.Context do
  @moduledoc """
  Runtime context passed to `Backpex.Preferences.Adapter` callbacks.

  A context captures where a preference read/write originated and gives
  adapters the handles they need (session, assigns, identity) without
  forcing every adapter to know about `Plug.Conn` or LiveView socket
  internals.

  Populate via one of the builders:

  - `from_mount/2` — LiveView mount / on_mount hook (read path).
  - `from_conn/1` — Plug controller (write path over HTTP).
  - `from_socket/2` — server-side preference writes from a LiveView.
  - `coerce/1` — wraps a bare session map so callers that only have a
    session on hand can still use the dispatcher.

  ## The `identity` field

  `identity` holds the current user's identifier as returned by the configured
  identity resolver (see `Backpex.Preferences`). It is `nil` before the
  dispatcher runs resolution, `:unidentified` when the resolver could not find
  a user, or any term the resolver returned on success (usually a user id).

  Resolution runs per dispatcher call (per `get`/`put`/`get_map`), not once
  per session. The resolved value is stashed on `ctx.identity` so adapter
  callbacks invoked during the same dispatch reuse the same identity, but
  the resolver re-runs on the next dispatcher call. Keep it cheap.
  """

  alias __MODULE__

  @type source :: :mount | :controller | :server
  @type identity :: term() | :unidentified | nil

  @type t :: %__MODULE__{
          source: source(),
          session: map(),
          assigns: map(),
          identity: identity()
        }

  defstruct source: :mount, session: %{}, assigns: %{}, identity: nil

  @doc """
  Build a context for a read originating at LiveView mount.

  `assigns` defaults to `%{}` for callers that only have a session on hand.
  """
  @spec from_mount(map(), map()) :: t()
  def from_mount(session, assigns \\ %{}) when is_map(session) and is_map(assigns) do
    %Context{source: :mount, session: session, assigns: assigns}
  end

  @doc """
  Build a context from a `%Plug.Conn{}` (write path over HTTP).

  Extracts the session and assigns from the conn and discards the conn
  itself — adapters receive the extracted values and never see the `conn`
  directly, which keeps adapter code free of a `Plug.Conn` dependency.
  """
  @spec from_conn(Plug.Conn.t()) :: t()
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
  @spec from_socket(map(), map()) :: t()
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
  @spec coerce(t() | map()) :: t()
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
  Returns `%{ctx | identity: identity}`.

  Called by the dispatcher after it runs the configured identity resolver
  on each read/write. Adapter callbacks for that single dispatch receive
  the already-resolved value; the resolver itself runs once per dispatcher
  call, not once per session.
  """
  @spec put_identity(t(), identity()) :: t()
  def put_identity(%Context{} = ctx, identity), do: %{ctx | identity: identity}
end
