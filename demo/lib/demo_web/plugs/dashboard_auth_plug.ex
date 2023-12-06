defmodule DemoWeb.DashboardAuthPlug do
  @moduledoc false
  @behaviour Plug

  @impl Plug
  def init(_opts), do: nil

  @impl Plug
  def call(conn, _opts) do
    case enabled?() do
      true -> Plug.BasicAuth.basic_auth(conn, username: username(), password: password())
      false -> conn
    end
  end

  defp enabled?, do: Application.fetch_env!(:demo, __MODULE__)[:enabled]
  defp username, do: Application.fetch_env!(:demo, __MODULE__)[:username]
  defp password, do: Application.fetch_env!(:demo, __MODULE__)[:password]
end
