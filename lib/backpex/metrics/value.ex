defmodule Backpex.Metrics.Value do
  @moduledoc """
  Value metrics display only a single value. This value is computed from the items of the current index view with the
  given aggregate. The value is processed by the specified formatting function and output in the frontend.

  ## Options

    * `:module` - Defines the module to handle the metric.
    * `:label` - Label text to define a headline for the metric.
    * `:aggregate` - The aggregate to compute, e.g. `{:sum, :quantity}`. See `t:Backpex.Metric.aggregate/0`.
    * `:where` - Optional expression that limits the items, e.g. `[published: true]` or
      `expr(likes > 10)`, see `Backpex.Expr`.
    * `:select` - Only for `Backpex.Adapters.Ecto`: a dynamic query expression to select instead of an aggregate,
      usually an aggregate function.
    * `:format` - Optional format function to post-process the value to display in frontend.
    * `:class` - Optional extra css classes to be passed to the metric box.

  ## Example

  In the following example we have a live resource `products` with a value `quantity`. We use the `aggregate` option here
  to add up the `quantity` value of all products currently active in the index view.

      @impl Backpex.LiveResource
      def metrics do
        [
          total_quantity: %{
            module: Backpex.Metrics.Value,
            label: "In Stock",
            class: "w-1/3",
            aggregate: {:sum, :quantity},
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

  @doc """
  Formats the selected data to display in frontend.
  """
  @impl Backpex.Metric
  def format(data, _format) when data == nil, do: "—"
  def format(data, format) when format == nil, do: data
  def format(data, format), do: format.(data)
end
