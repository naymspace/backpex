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
    * `:where` - an optional expression that limits the items, e.g. `[published: true]` or `expr(likes > 10)`. See
      `Backpex.Expr`.

  `Backpex.Adapters.Ecto` also takes a `:select` expression instead of an aggregate.

  ## Filters

  A metric covers the items after the search and the active filters of the index view. With `:ignore_filters`, it
  ignores the given filters, e.g. `ignore_filters: [:status]` for a metric of the items of every status while the index
  view shows the items of one status. The option applies to the query that `c:data/3` receives, too.

  ## Data of your own

  A metric module that gets its data in another way, e.g. from a function of your context module, implements `c:data/3`.
  Backpex then calls it instead of the adapter, with the `Backpex.Query` of the items of the index view: the items of
  the resource after the search and the active filters (except the ones of `:ignore_filters`), on all pages. It is the
  query the adapter would compute the aggregate for.

  To get these items, read the query with `Backpex.Resource.read/1`, or count them with `Backpex.Resource.count/1`:

      @impl Backpex.Metric
      def data(_metric, query, _assigns) do
        {:ok, items} = Backpex.Resource.read(query)

        items |> Enum.map(&MyApp.Orders.total/1) |> Enum.sum()
      end

  A metric that reads its data elsewhere has to limit it itself, e.g. with the search term of `query.search` and the
  values of the filters and the current user from the assigns.
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

  Receives the metric, the query of the items of the index view (see `Backpex.Query`) and the assigns of the index view.
  """
  @callback data(metric :: map(), query :: Backpex.Query.t(), assigns :: map()) :: term()

  @optional_callbacks data: 3

  # Backpex no longer calls `query/3` and `data/2`, so the adapter would compute other data than the metric did. Modules
  # that only declare `@behaviour Backpex.Metric` are refused when Backpex computes the metric, see
  # `Backpex.Resource.metrics/3`.
  @removed_callbacks [
    {{:query, 3}, "metrics no longer query their data"},
    {{:data, 2}, "Backpex calls data/3 with the query of the index view"}
  ]

  @doc false
  defmacro __before_compile__(env) do
    if not Module.defines?(env.module, {:data, 3}, :def) do
      for {{name, arity}, hint} <- @removed_callbacks, Module.defines?(env.module, {name, arity}, :def) do
        raise CompileError,
          file: env.file,
          description: """
          #{inspect(env.module)} defines #{name}/#{arity}, but #{hint}. Implement Backpex.Metric.data/3 instead, see \
          the guide on upgrading to v0.24.
          """
      end
    end

    :ok
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
