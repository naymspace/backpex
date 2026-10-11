defmodule Backpex.Adapters.Ecto.Metric do
  @moduledoc """
  The Ecto-specific callback of metrics.

  A metric describes its value with the `:aggregate` and `:where` options, see `Backpex.Metric`. A metric module that
  needs more, e.g. several values for a chart, can implement `c:query/3` instead. Only `Backpex.Adapters.Ecto` calls
  it, so such a metric only works with this adapter.

      defmodule MyAppWeb.Metrics.OrdersPerStatus do
        use BackpexWeb, :metric

        @behaviour Backpex.Adapters.Ecto.Metric

        import Ecto.Query

        @impl Backpex.Adapters.Ecto.Metric
        def query(query, _metric, repo) do
          query
          |> group_by([order], order.status)
          |> select([order], {order.status, count()})
          |> repo.all()
        end

        # ...the callbacks of `Backpex.Metric`
      end
  """

  @doc """
  Queries the data of the metric. Takes precedence over the `:aggregate` and `:select` options of the metric.

  Receives the query of the items on the index view without select, preloads and group by, the metric and the repo.
  """
  @callback query(query :: Ecto.Query.t(), metric :: map(), repo :: module()) :: term()
end
