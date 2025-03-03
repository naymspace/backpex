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
    class = "mb-4 w-full rounded-btn bg-base-100 p-4 px-5 shadow-xs ring-1 ring-base-100"

    case Map.get(metric, :class) do
      nil -> class
      extra_class -> class <> " " <> extra_class
    end
  end
end
