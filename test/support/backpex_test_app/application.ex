defmodule BackpexTestApp.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      BackpexTestAppWeb.Telemetry,
      BackpexTestApp.Repo,
      {DNSCluster, query: Application.get_env(:backpex, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: BackpexTestApp.PubSub},
      # Start a worker by calling: BackpexTestApp.Worker.start_link(arg)
      # {BackpexTestApp.Worker, arg},
      # Start to serve requests, typically the last entry
      BackpexTestAppWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: BackpexTestApp.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    BackpexTestAppWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
