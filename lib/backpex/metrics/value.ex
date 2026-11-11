defmodule Backpex.Metrics.Value do
  @config_schema [
    module: [
      doc: "The metric module, `Backpex.Metrics.Value`.",
      type: :atom,
      required: true
    ],
    label: [
      doc: "The headline of the metric.",
      type: :string,
      required: true
    ],
    select: [
      doc: "Dynamic query expression defining the column to select. This is usually an aggregate function.",
      type: :any,
      required: true
    ],
    format: [
      doc: "A function to post-process the selected value from the database to display in frontend.",
      type: {:or, [{:fun, 1}, nil]}
    ],
    class: [
      doc: "Extra css classes to be passed to the metric box.",
      type: {:or, [:string, {:list, :any}]}
    ]
  ]

  @moduledoc """
  Value metrics display only a single value. This value is generated from the current index query by applying the given
  aggregate function. The selected value is processed by the specified formatting function and output in the frontend.

  ## Options

  Any other key raises a configuration error when the index view loads.

  #{NimbleOptions.docs(@config_schema)}

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
      |> assign(:value, metric.module.format(metric.data, Map.get(metric, :format)))
      |> assign(:class, Map.get(assigns.metric, :class))

    ~H"""
    <div class={["card bg-base-100 mb-4 shadow-sm", @class]}>
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

  @impl Backpex.Metric
  def config_schema, do: @config_schema

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
