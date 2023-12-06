defmodule Backpex.Metric do
  @moduledoc ~S"""
  Behaviour implemented by all metrics.

  Metrics are info boxes for your resources displaying key indicators prominently on the index view in your application.
  An example could be to show the current total of all orders received today. You may create your own metrics by
  implementing this behaviour.
  """

  @doc """
  Used to render the metric as a heex template on the index views.
  """
  @callback render(assigns :: map()) :: %Phoenix.LiveView.Rendered{}
  @callback query(query :: Ecto.Queryable.t(), select :: any(), repo :: Ecto.Repo.t()) ::
              Ecto.Schema.t() | term() | nil
  @callback format(data :: any(), format :: any()) :: term()

  @doc """
  Determine if metrics are visible for given live_resource.
  """
  def metrics_visible?(%{} = visibility, resource) when is_atom(resource) do
    metrics_visible?(visibility, Atom.to_string(resource))
  end

  def metrics_visible?(%{} = visibility, resource) do
    Map.get(visibility, resource, true)
  end

  @doc """
  Builds string of css classes for basic metric box
  """
  def metric_box_class(metric) do
    class = "mb-4 w-full rounded-md bg-white p-4 px-5 shadow-sm ring-1 ring-gray-200"

    case Map.get(metric, :class) do
      nil -> class
      extra_class -> class <> " " <> extra_class
    end
  end

  @doc """
  Load and append the corresponding metric value(s) via the module's query for
  every metric in the given list. Query's are only performed if metrics are
  marked as visible for the give live resource.
  """
  def load_data_for_visible(metrics, visibility, resource, query, repo) do
    Enum.map(metrics, fn {key, metric} ->
      case metrics_visible?(visibility, resource) do
        true ->
          data =
            query
            |> Ecto.Query.exclude(:select)
            |> Ecto.Query.exclude(:preload)
            |> Ecto.Query.exclude(:group_by)
            |> metric.module.query(metric.select, repo)

          {key, Map.put(metric, :data, data)}

        _visible ->
          {key, metric}
      end
    end)
  end
end
