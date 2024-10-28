# Ordering

You can configure the ordering of the resource index page. By default, the resources are ordered by the `id` field in ascending order.

## Configuration

To configure the ordering of the resource index page, use the `init_order` option in your resource configuration file. This option accepts either a map or a function that returns a map.

The map must contain the following keys:

- `:by` - The field to order by (atom)
- `:direction` - The order direction (`:asc` for ascending or `:desc` for descending)

### Using a Map

You can directly specify the ordering with a map:

```elixir
# in your resource configuration file (live resource)
use Backpex.LiveResource,
  # ...other options
  init_order: %{by: :inserted_at, direction: :desc}
```

This configuration orders resources by the inserted_at field in descending order.

### Using a Function

```elixir
# in your resource configuration file (live resource)
use Backpex.LiveResource,
  # ...other options
  init_order: &__MODULE__.init_order/1

def init_order(_assigns) do
  %{by: :username, direction: :asc}
end
```

The function must:

- Take one argument (assigns)
- Return a map with `:by` and `:direction` keys

This approach allows you to determine the ordering based on runtime conditions or user-specific data in assigns.

> #### Important {: .info}
>
> Note that it is not possible to use an anonymous function for `init_order` configuration. You must refer to a public function defined within a module.
