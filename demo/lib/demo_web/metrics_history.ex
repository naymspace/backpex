defmodule DemoWeb.MetricsStorage do
  @moduledoc false
  use GenServer

  @history_buffer_size 50

  def metrics_history(metric) do
    GenServer.call(__MODULE__, {:data, metric})
  end

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl GenServer
  def init(metrics) do
    Process.flag(:trap_exit, true)

    metric_histories_map =
      metrics
      |> Map.new(fn metric ->
        attach_handler(metric)
        {metric, CircularBuffer.new(@history_buffer_size)}
      end)

    {:ok, metric_histories_map}
  end

  @impl GenServer
  def terminate(_reason, metrics) do
    for metric <- metrics do
      :telemetry.detach({__MODULE__, metric, self()})
    end

    :ok
  end

  defp attach_handler(%{event_name: name_list} = metric) do
    :telemetry.attach({__MODULE__, metric, self()}, name_list, &__MODULE__.handle_event/4, metric)
  end

  def handle_event(_event_name, data, metadata, metric) do
    if data = Phoenix.LiveDashboard.extract_datapoint_for_metric(metric, data, metadata) do
      GenServer.cast(__MODULE__, {:telemetry_metric, data, metric})
    end
  end

  @impl GenServer
  def handle_cast({:telemetry_metric, data, metric}, state) do
    {:noreply, update_in(state[metric], &CircularBuffer.insert(&1, data))}
  end

  @impl GenServer
  def handle_call({:data, metric}, _from, state) do
    if history = state[metric] do
      {:reply, CircularBuffer.to_list(history), state}
    else
      {:reply, [], state}
    end
  end
end
