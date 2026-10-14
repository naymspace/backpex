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

  `Backpex.Adapters.Ecto` also takes a `:select` expression instead of an aggregate.

  ## Data of your own

  A metric module that gets its data in another way, e.g. from a function of your context module, implements `c:data/2`.
  Backpex then calls it instead of the adapter. It receives the assigns of the index view, so it can read the values of
  the active filters from `:filter_values`.

  As the adapter doesn't query the data, neither the search, the filters nor the `item_query` of `Backpex.Adapters.Ecto`
  limit it. `c:data/2` has to limit the data itself, e.g. to the items the current user may see.
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
  Returns the data of the metric. Implement it to get the data in another way than with the `:aggregate` the adapter
  computes, see the [Data of your own](#module-data-of-your-own) section.

  Receives the metric and the assigns of the index view, which hold the validated values of the active filters under
  `:filter_values`.
  """
  @callback data(metric :: map(), assigns :: map()) :: term()

  @optional_callbacks data: 2

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
