defmodule DemoWeb.RedirectController do
  @moduledoc false

  use DemoWeb, :controller

  def redirect_to_users(conn, _params) do
    conn
    |> Phoenix.Controller.redirect(to: ~p"/admin/users")
    |> Plug.Conn.halt()
  end
end
