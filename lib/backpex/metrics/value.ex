defmodule Backpex.Metrics.Value do
  @moduledoc """
  Value metrics display only a single value. This value is generated from the current index query by applying the given
  aggregate function. The selected value is processed by the specified formatting function and output in the frontend.

  ## Options

    * `:module` - Defines the module to handle the metric.
    * `:label` - Label text to define a headline for the metric.
    * `:select` - Dynamic query expression defining the column to select. This is usually an aggregate function.
    * `:format` - Optional format function to post-process the selected value from the database to display in frontend.
    * `:class` - Optional extra css classes to be passed to the metric box.

  ## Example

  In the following example we have a live resource `products` with a value `quantity`. We use the `select` option here
  to pass an aggregate function that adds up the `quantity` value of all products currently active in the index view.

      @impl Backpex.LiveResource
      def metrics do
        [
          total_quantity: %{
            module: Backpex.Metrics.Value,
            label: "In Stock",
            class: "w-1/3",
            select: dynamic([i], sum(i.quantity)),
            format: fn value ->
              Integer.to_string(value) <> " Products"
            end
          }
        ]
      end
  """

  use BackpexWeb, :metric

  attr :metric, :any, required: true, doc: "the metric to be rendered"

  @impl Backpex.Metric
  def render(assigns) do
    %{metric: metric} = assigns

    assigns =
      assigns
      |> assign(:label, metric.label)
      |> assign(:value, metric.module.format(metric.data, metric.format))
      |> assign(:class, Map.get(assigns.metric, :class))

    ~H"""
    <div class={["card bg-base-100 shadow-xs mb-4", @class]}>
      <div class="card-body p-4">
        <p class="card-title text-base-content/60 text-sm font-normal">
          {@label}
        </p>
        <p class="text-base-content text-2xl font-semibold">
          {@value}
        </p>
      </div>
    </div>
    """
  end

  @doc """
  Performs database select to query the value of the metric
  """
  @impl Backpex.Metric
  def query(query, select, repo) do
    query
    |> select(^select)
    |> repo.one()
  end

  @doc """
  Formats the selected data to display in frontend.
  """
  @impl Backpex.Metric
  def format(data, _format) when data == nil, do: "—"
  def format(data, format) when format == nil, do: data
  def format(data, format), do: format.(data)
end
