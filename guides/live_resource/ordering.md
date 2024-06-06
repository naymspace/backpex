# Ordering

You can configure the ordering of the resource index page. By default, the resources are ordered by the `id` field in ascending order.

## Configuration

To configure the ordering of the resource index page, you need to provide an `init_order` option in the resource configuration file:

```elixir
# in your resource configuration file

use Backpex.LiveResource,
    ...,
    init_order: %{by: :inserted_at, direction: :desc}
```

The example above will order the resources by the `inserted_at` field in descending order.
