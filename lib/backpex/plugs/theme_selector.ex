defmodule Backpex.Plug.ThemeSelector do
  import Plug.Conn

  @backpex_key "backpex"
  @select_theme_key "select_theme"
  @theme_key "theme"

  def init(default), do: default

  def call(conn, _default) do
    session = get_session(conn)
    theme = session[@backpex_key][@select_theme_key][@theme_key]

    conn
    |> assign(:theme, theme)
  end
end
