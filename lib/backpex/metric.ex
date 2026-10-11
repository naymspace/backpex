defmodule Backpex.Metric do
  @moduledoc ~S"""
  Behaviour implemented by all metrics.

  Metrics are info boxes for your resources displaying key indicators prominently on the index view in your application.
  An example could be to show the current total of all orders received today. You may create your own metrics by
  implementing this behaviour.

  ## Aggregates

  A metric doesn't query its data itself. The adapter of the LiveResource computes it from the items on the index view,
  after search and filters, with these options of the metric:

    * `:aggregate` - `:count` for the number of items, or a tuple of `:count`, `:sum`, `:avg`, `:min` or `:max` and the
      name of a field, e.g. `{:sum, :quantity}`.
    * `:where` - an optional condition that limits the items, e.g. `{:==, :published, true}`. See
      `t:Backpex.Filter.condition/0`.

  `Backpex.Adapters.Ecto` also takes a `:select` expression instead of an aggregate, and calls
  `c:Backpex.Adapters.Ecto.Metric.query/3` if the metric module implements it.
  """

  alias Phoenix.LiveView.Rendered

  @typedoc """
  The aggregate a metric computes, see the [Aggregates](#module-aggregates) section.
  """
  @type aggregate :: :count | {:count | :sum | :avg | :min | :max, atom()}

  @doc """
  Used to render the metric as a heex template on the index views.
  """
  @callback render(assigns :: map()) :: %Rendered{}

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
end
