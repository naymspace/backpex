defmodule DemoWeb.Telemetry do
  @moduledoc false

  use Supervisor
  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl Supervisor
  def init(_arg) do
    children = [
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      # Phoenix Metrics
      summary("phoenix.endpoint.stop.duration", unit: {:native, :millisecond}),
      summary("phoenix.router_dispatch.stop.duration", tags: [:route], unit: {:native, :millisecond}),
      summary("phoenix.live_view.mount.stop.duration",
        tags: [:view],
        tag_values: fn metadata -> Map.put(metadata, :view, "#{inspect(metadata.socket.view)}") end,
        unit: {:native, :millisecond}
      ),
      summary("phoenix.live_view.handle_params.stop.duration",
        tags: [:view],
        tag_values: fn metadata -> Map.put(metadata, :view, "#{inspect(metadata.socket.view)}") end,
        unit: {:native, :millisecond}
      ),
      summary("phoenix.live_view.handle_event.stop.duration",
        tags: [:view, :event],
        tag_values: fn metadata -> Map.put(metadata, :view, "#{inspect(metadata.socket.view)}") end,
        unit: {:native, :millisecond}
      ),

      # Database Metrics
      summary("demo.repo.query.total_time", unit: {:native, :millisecond}),
      summary("demo.repo.query.decode_time", unit: {:native, :millisecond}),
      summary("demo.repo.query.query_time", unit: {:native, :millisecond}),
      summary("demo.repo.query.queue_time", unit: {:native, :millisecond}),
      summary("demo.repo.query.idle_time", unit: {:native, :millisecond}),

      # VM Metrics
      summary("vm.memory.total", unit: {:byte, :megabyte}),
      summary("vm.total_run_queue_lengths.total"),
      summary("vm.total_run_queue_lengths.cpu"),
      summary("vm.total_run_queue_lengths.io"),

      # Bandit Metrics
      summary("bandit.request.stop.duration", unit: {:native, :millisecond})
    ]
  end

  defp periodic_measurements do
    [
      # A module, function and arguments to be invoked periodically.
      # This function must call :telemetry.execute/3 and a metric must be added above.
      # {DemoWeb, :count_users, []}
    ]
  end
end
