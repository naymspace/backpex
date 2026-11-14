# Metrics

Metrics are info boxes above the table of the index view. Each one shows a key figure of the resource, e.g. the sum of all likes or the number of posts.

Backpex ships with one metric, `Backpex.Metrics.Value`, which shows a single value selected from the database. You can add your own with the `Backpex.Metric` behaviour.

## Configuration

To add metrics to a resource, you need to implement the [metrics/0](Backpex.LiveResource.html#c:metrics/0) callback in your resource configuration file. It has to return a keyword list with an identifier and a map of options for each metric. Metrics are displayed in the provided order.

```elixir
# in your resource configuration file
import Ecto.Query

@impl Backpex.LiveResource
def metrics do
  [
    total_likes: %{
      module: Backpex.Metrics.Value,
      label: "Total likes",
      class: "lg:w-1/4",
      select: dynamic([p], sum(p.likes)),
      format: fn value -> Integer.to_string(value) <> " likes" end
    },
    posts: %{
      module: Backpex.Metrics.Value,
      label: "Posts",
      class: "lg:w-1/4",
      select: dynamic([p], count(p.id)),
      format: nil
    }
  ]
end
```

The example above will show two boxes: the sum of the `likes` column with the suffix "likes" and the number of posts.

The `Backpex.Metrics.Value` metric reads these keys from the map:

| Option | Value | Purpose |
|--------|-------|---------|
| `:module` | module | The metric module, here `Backpex.Metrics.Value` |
| `:label` | string | The headline of the box |
| `:select` | `dynamic` expression | What to select from the query of the index view, usually an aggregate such as `sum`, `count`, `avg`, `min` or `max`. The first binding is the schema of the resource |
| `:format` | function with one argument or `nil` | Turns the selected value into what is displayed. With `nil` the value is displayed as it is |
| `:class` | string | Extra CSS classes for the box, e.g. a width. May be left out |

> #### Info {: .info}
>
> The options of a metric are not validated. `:module`, `:label`, `:select` and `:format` have no default and have to be present, so set `format: nil` if you do not need a format function.

## Search and filters

A value metric is computed for the items the admin currently sees in the table, on all pages. Backpex builds the same query as for the table, including your [item query](item-query.md), the search and the active filters, and replaces its `select` with the one of the metric. Ordering and pagination are not part of that query.

The metrics are computed again whenever the table is loaded again, e.g. when the admin searches or changes a filter.

## Ignoring filters

With the `:ignore_filters` option, a metric is computed without some of the active filters. It takes the names of the filters as in [filters/0](Backpex.LiveResource.html#c:filters/0). The search and the other filters still apply.

```elixir
# The index view has a `:published` filter. This box shows the number of all posts, whatever the filter is set to.
all_posts: %{
  module: Backpex.Metrics.Value,
  label: "All posts",
  select: dynamic([p], count(p.id)),
  ignore_filters: [:published],
  format: nil
}
```

## Formatting

The function in `:format` receives the selected value and returns what is displayed, usually a string.

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

You can create a custom metric by using the `metric` macro from the `BackpexWeb` module. It implements the `Backpex.Metric` behaviour, uses `Phoenix.Component` and imports `Ecto.Query`.

| Callback | Purpose |
|----------|---------|
| `render/1` | Renders the metric. The assigns contain the map from `metrics/0` as `@metric`, with the data of the metric under `:data` |
| `format/2` | Formats the data. Backpex does not call it, your `render/1` does |
| `data/2` | Returns the data. Receives the map from `metrics/0` and the assigns of the index view |
| `query/3` | Returns the data from the query of the index view. Receives that query, the `:select` option and the repo. Not called if the module implements `data/2` |

A metric module implements `render/1`, `format/2` and one of `data/2` and `query/3`.

Here is an example of a metric that gets its number from a function of your application:

```elixir
defmodule MyAppWeb.Metrics.Drafts do
  use BackpexWeb, :metric

  @impl Backpex.Metric
  def data(_metric, assigns), do: MyApp.Blog.count_drafts(assigns.filter_values)

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

A metric with `data/2` does not follow the search and filters by itself. The assigns hold the validated values of the active filters under `:filter_values`, so the metric can pass them on, as in the example above.
