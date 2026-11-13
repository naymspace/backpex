defmodule DemoWeb.DashboardAuthPlug do
  @moduledoc """
  Protects the LiveDashboard with basic auth.

  Configured in `config/runtime.exs`:

    * `:required` - whether credentials are required. Only an explicit `false` lets requests pass without them.
    * `:username` and `:password` - the basic auth credentials.

  When credentials are required but one of them is missing or empty, every request is answered with 404, so a
  deployment without credentials has no reachable dashboard.
  """
  @behaviour Plug

  import Plug.Conn

  @impl Plug
  def init(_opts), do: nil

  @impl Plug
  def call(conn, _opts) do
    config = Application.get_env(:demo, __MODULE__, [])
    username = config[:username]
    password = config[:password]

    cond do
      config[:required] == false ->
        conn

      present?(username) and present?(password) ->
        Plug.BasicAuth.basic_auth(conn, username: username, password: password)

      true ->
        conn |> send_resp(:not_found, "Not Found") |> halt()
    end
  end

  defp present?(value), do: is_binary(value) and value != ""
end
