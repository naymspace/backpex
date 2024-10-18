defmodule Demo.Application do
  @moduledoc false

  use Application

  @impl Application
  def start(_type, _args) do
    topologies = Application.get_env(:libcluster, :topologies)

    children = [
      {Cluster.Supervisor, [topologies, [name: Sourceboat.ClusterSupervisor]]},
      {Phoenix.PubSub, name: Demo.PubSub},
      Demo.Repo,
      Demo.RepoAsh,
      DemoWeb.Telemetry,
      {DemoWeb.MetricsStorage, DemoWeb.Telemetry.metrics()},
      DemoWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: Demo.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl Application
  def config_change(changed, _new, removed) do
    DemoWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
