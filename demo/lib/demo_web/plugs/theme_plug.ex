defmodule DemoWeb.ThemePlug do
  @moduledoc """
  Plug that reads the theme preference from the session and assigns it to conn.

  This enables server-side rendering of the correct theme on initial page load,
  preventing UI flickering.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    session = get_session(conn)
    theme = Backpex.Preferences.get(session, "global.theme", default: "light")

    assign(conn, :theme, theme)
  end
end
