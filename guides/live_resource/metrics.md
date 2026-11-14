# Metrics

Metrics are info boxes above the table of the index view. Each one shows a key figure of the resource, e.g. the sum of all likes or the number of posts.

Backpex ships with one metric, `Backpex.Metrics.Value`, which shows a single value computed from the items of the index view. You can add your own with the `Backpex.Metric` behaviour.

## Configuration

To add metrics to a resource, you need to implement the [metrics/0](Backpex.LiveResource.html#c:metrics/0) callback in your resource configuration file. It has to return a keyword list with an identifier and a map of options for each metric. Metrics are displayed in the provided order.

```elixir
# in your resource configuration file
@impl Backpex.LiveResource
def metrics do
  [
    total_likes: %{
      module: Backpex.Metrics.Value,
      label: "Total likes",
      class: "lg:w-1/4",
      aggregate: {:sum, :likes},
      format: fn value -> Integer.to_string(value) <> " likes" end
    },
    published_posts: %{
      module: Backpex.Metrics.Value,
      label: "Published posts",
      class: "lg:w-1/4",
      aggregate: :count,
      where: [published: true],
      format: nil
    }
  ]
end
```

The example above will show two boxes: the sum of the `likes` field with the suffix "likes" and the number of published posts.

The `Backpex.Metrics.Value` metric reads these keys from the map:

| Option | Value | Purpose |
|--------|-------|---------|
| `:module` | module | The metric module, here `Backpex.Metrics.Value` |
| `:label` | string | The headline of the box |
| `:aggregate` | `:count` or `{function, field}` | What to compute: `:count` for the number of items, or a tuple of `:count`, `:sum`, `:avg`, `:min` or `:max` and the name of a field, e.g. `{:sum, :likes}`. See `t:Backpex.Metric.aggregate/0` |
| `:where` | expression | Limits the items the aggregate is computed from, e.g. `[published: true]`. May be left out |
| `:select` | `dynamic` expression | Only with `Backpex.Adapters.Ecto`: what to select instead of an `:aggregate`, see [Selecting with Ecto](#selecting-with-ecto) |
| `:format` | function with one argument or `nil` | Turns the computed value into what is displayed. With `nil` the value is displayed as it is |
| `:class` | string | Extra CSS classes for the box, e.g. a width. May be left out |

> #### Info {: .info}
>
> The options of a metric are not validated. `:module`, `:label`, `:aggregate` (or `:select`) and `:format` have no default and have to be present, so set `format: nil` if you do not need a format function.

The `:where` option takes an expression, see `Backpex.Expr`. A keyword list stands for fields that equal values. For other conditions, write the expression with `Backpex.Expr.expr/1`:

```elixir
# in your resource configuration file
import Backpex.Expr, only: [expr: 1]

@impl Backpex.LiveResource
def metrics do
  [
    popular_posts: %{
      module: Backpex.Metrics.Value,
      label: "Popular posts",
      aggregate: :count,
      where: expr(likes > 10),
      format: nil
    }
  ]
end
```

### Selecting with Ecto

A metric doesn't query its data itself: the adapter of the LiveResource computes the aggregate. `Backpex.Adapters.Ecto` also takes a `:select` with an Ecto `dynamic` expression instead of an `:aggregate`, for values an aggregate can't express. The first binding is the schema of the resource. Such a metric only works with the Ecto adapter.

```elixir
# in your resource configuration file
import Ecto.Query

@impl Backpex.LiveResource
def metrics do
  [
    likes_per_post: %{
      module: Backpex.Metrics.Value,
      label: "Likes per post",
      select: dynamic([p], sum(p.likes) / count(p.id)),
      format: nil
    }
  ]
end
```

## Search and filters

A value metric is computed for the items the admin currently sees in the table, on all pages. The adapter computes it for the same items as the table, after your [item query](item-query.md), the search and the active filters, limited by the `:where` of the metric. Ordering and pagination play no part.

The metrics are computed again whenever the table is loaded again, e.g. when the admin searches or changes a filter.

## Formatting

The function in `:format` receives the computed value and returns what is displayed, usually a string.

When the database returns `NULL`, e.g. for a `sum` when no item matches the search and filters, `Backpex.Metrics.Value` displays "—" and does not call the function. The function therefore does not have to handle `nil`.

## Visibility

When a resource has metrics, the index view shows a button next to the search that lets the admin hide and show all metrics of that resource. Hidden metrics are not computed.

By default, this choice is kept in the LiveView only and the metrics are visible again the next time the index view is opened. To remember it, add `:metrics` to the `persist` option of the resource:

```elixir
use Backpex.LiveResource,
  adapter_config: [...],
  persist: [:metrics]
```

Backpex then stores the choice with `Backpex.Preferences` under the key `resource:<Module>:metrics_visible`. See the [User Preferences](user-preferences.md#opt-in-persistence-for-ordering-filters-columns-metrics) guide for where preferences are stored.

## Placement

The metrics are rendered in the `:metrics` slot of the index view. You can add content above them or replace them with the [render_resource_slot/3](Backpex.LiveResource.html#c:render_resource_slot/3) callback, see the [Templates](templates.md) guide.

## Custom Metrics

You can create a custom metric by using the `metric` macro from the `BackpexWeb` module. It implements the `Backpex.Metric` behaviour and uses `Phoenix.Component`.

| Callback | Purpose |
|----------|---------|
| `render/1` | Renders the metric. The assigns contain the map from `metrics/0` as `@metric`, with the data of the metric under `:data` |
| `format/2` | Formats the data. Backpex does not call it, your `render/1` does |
| `data/3` | Returns the data. Receives the map from `metrics/0`, the criteria of the index view and the assigns of the index view. May be left out |

A metric module implements `render/1` and `format/2`. Without `data/3`, the adapter computes the data from the `:aggregate` of the metric, as for `Backpex.Metrics.Value`. With `data/3`, Backpex calls it instead of the adapter.

Here is an example of a metric that gets its number from a function of your application:

```elixir
defmodule MyAppWeb.Metrics.Drafts do
  use BackpexWeb, :metric

  @impl Backpex.Metric
  def data(_metric, criteria, _assigns), do: MyApp.Blog.count_drafts(criteria[:filter_values])

  @impl Backpex.Metric
  def format(data, _format), do: "#{data} drafts"

  @impl Backpex.Metric
  def render(assigns) do
    ~H"""
    <div class="card bg-base-100 mb-4 shadow-sm">
      <div class="card-body p-4">
        <p class="card-title text-base-content/60 text-sm font-normal">{@metric.label}</p>
        <p class="text-base-content text-2xl font-semibold">{format(@metric.data, nil)}</p>
      </div>
    </div>
    """
  end
end
```

```elixir
# in your resource configuration file
@impl Backpex.LiveResource
def metrics do
  [
    drafts: %{module: MyAppWeb.Metrics.Drafts, label: "Drafts"}
  ]
end
```

The criteria hold the search under `:search`, and the validated values and the configurations of the active filters under `:filter_values` and `:filter_configs`. A metric with `data/3` does not follow the search and filters by itself: it passes the criteria on, as in the example above, or hands them to `Backpex.Resource.list/4` or `Backpex.Resource.count/4` to get the items of the index view:

```elixir
@impl Backpex.Metric
def data(_metric, criteria, assigns) do
  {:ok, orders} = Backpex.Resource.list(criteria, assigns.fields, assigns, assigns.live_resource)

  orders |> Enum.map(&MyApp.Orders.total/1) |> Enum.sum()
end
```

A metric module that still defines `data/2` or `query/3` of earlier versions does not compile, see the [upgrade guide](../upgrading/v0.25.md).
