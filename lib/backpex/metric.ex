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

  A metric module that gets its data in another way, e.g. from a function of your context module, implements `c:data/3`.
  Backpex then calls it instead of the adapter, with the criteria of the index view: the search under `:search`, and the
  validated values and the configurations of the active filters under `:filter_values` and `:filter_configs`. These are
  the criteria the adapter would compute the aggregate for.

  The criteria don't limit the data by themselves. To get the items of the index view, after the `item_query` of
  `Backpex.Adapters.Ecto`, the search and the filters, pass them to `Backpex.Resource.list/4` or
  `Backpex.Resource.count/4`:

      @impl Backpex.Metric
      def data(_metric, criteria, assigns) do
        {:ok, items} = Backpex.Resource.list(criteria, assigns.fields, assigns, assigns.live_resource)

        items |> Enum.map(&MyApp.Orders.total/1) |> Enum.sum()
      end

  A metric that reads its data elsewhere has to limit it itself, e.g. with the search string from `criteria[:search]`,
  the values of the filters from `criteria[:filter_values]` and the current user from the assigns.
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

  Receives the metric, the criteria of the index view (the same criteria `c:Backpex.Adapter.metric/5` gets) and the
  assigns of the index view.
  """
  @callback data(metric :: map(), criteria :: keyword(), assigns :: map()) :: term()

  @optional_callbacks data: 3

  # Backpex no longer calls `query/3`, so the adapter would compute other data than the metric did. Modules that only
  # declare `@behaviour Backpex.Metric` are refused when Backpex computes the metric, see `Backpex.Resource.metric/5`.
  @doc false
  defmacro __before_compile__(env) do
    if Module.defines?(env.module, {:query, 3}, :def) and not Module.defines?(env.module, {:data, 3}, :def) do
      raise CompileError,
        file: env.file,
        description: """
        #{inspect(env.module)} defines query/3, but metrics no longer query their data. Implement \
        Backpex.Metric.data/3 instead, see the guide on upgrading to v0.24.
        """
    end
  end

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
