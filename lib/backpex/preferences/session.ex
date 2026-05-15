defmodule Backpex.Preferences.Session do
  @moduledoc """
  Helpers for preserving the Backpex preferences session entry across
  `Plug.Conn.clear_session/1` calls.

  The Phoenix-generated `UserAuth.renew_session/2` pattern clears the session
  on login/logout and explicitly re-puts an allowlist of values. Apps that
  follow that pattern would silently drop the `Backpex.Preferences` session
  entry — theme, sidebar state, persisted filters/order/columns — unless they
  know the specific session key Backpex uses.

  These helpers wrap that dance so integrators do not hardcode the session
  key name in their auth code.

  ## Usage

  In your app's `UserAuth.renew_session/2`:

      def renew_session(conn, _user) do
        backpex_prefs = Backpex.Preferences.Session.preserve(conn)

        conn
        |> configure_session(renew: true)
        |> clear_session()
        |> then(&Backpex.Preferences.Session.restore(&1, backpex_prefs))
      end

  Both calls are no-ops when nothing is stored under the preferences key, so
  they are safe to add unconditionally.
  """

  alias Backpex.Preferences

  @doc """
  Returns the current value stored under `Backpex.Preferences.session_key/0`,
  or `nil` if nothing is stored.

  Call before `Plug.Conn.clear_session/1` to capture the value, then pass the
  result to `restore/2` afterwards.
  """
  @spec preserve(Plug.Conn.t()) :: term() | nil
  def preserve(%Plug.Conn{} = conn) do
    Plug.Conn.get_session(conn, Preferences.session_key())
  end

  @doc """
  Re-puts `value` under `Backpex.Preferences.session_key/0`.

  When `value` is `nil` (i.e. nothing was preserved), returns `conn`
  unchanged — the absence of a previous value is not an error.
  """
  @spec restore(Plug.Conn.t(), term() | nil) :: Plug.Conn.t()
  def restore(%Plug.Conn{} = conn, nil), do: conn

  def restore(%Plug.Conn{} = conn, value) do
    Plug.Conn.put_session(conn, Preferences.session_key(), value)
  end
end
