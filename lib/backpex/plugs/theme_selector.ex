defmodule Backpex.ThemeSelectorPlug do
  @moduledoc """
  Contains a plug that inserts the theme into the assigns
  """
  import Plug.Conn

  @backpex_key "backpex"
  @theme_key "theme"

  def init(default), do: default

  def call(conn, _default) do
    session = get_session(conn)
    theme = session[@backpex_key][@theme_key]

    assign(conn, :theme, theme)
  end
end
