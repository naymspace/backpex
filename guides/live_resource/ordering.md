# Ordering

You can configure the ordering of the resource index page. By default, resources
are ordered in ascending order by the LiveResource's configured `primary_key`
(`:id` unless you override it).

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

## URL Parameters

Users can change the ordering through URL parameters:

- `order_by` - The field to order by (must match an orderable field name)
- `order_direction` - Either `asc` or `desc`

For example: `/admin/posts?order_by=title&order_direction=desc`

### Validation

Backpex validates ordering parameters from the URL:

| Parameter | Validation | Invalid Value Behavior |
|-----------|------------|----------------------|
| `order_by` | Must be a field with `orderable: true` | Falls back to `init_order.by` |
| `order_direction` | Must be `asc` or `desc` | Falls back to `init_order.direction` |

Invalid URL parameters won't crash the application. Instead, they are silently replaced with the default values from your `init_order` configuration.

## Ordering Select Fields

`Backpex.Fields.Select` fields are ordered by the labels of their options instead of the stored values. `Backpex.Fields.MultiSelect` and `Backpex.Fields.Checkgroup` fields are ordered by the labels of their selected options, in the order of the options and joined with `", "`. If you translate the labels in an `options` function, the index view is ordered by the labels in the locale of the current user. See `Backpex.Fields.Select` for details.

## Custom Order Expressions

A field module can change the expression the index view is ordered by when the user orders by the field. Implement the `c:Backpex.Field.order_expression/4` callback in your [custom field](../fields/custom-fields.md) and return an `Ecto.Query.dynamic/2` expression.

## Disabling Ordering for Fields

By default, all fields are orderable. To disable ordering for a specific field, set `orderable: false` in the field configuration:

```elixir
@impl Backpex.LiveResource
def fields do
  [
    title: %{
      module: Backpex.Fields.Text,
      label: "Title"
    },
    body: %{
      module: Backpex.Fields.Textarea,
      label: "Body",
      orderable: false  # Users cannot order by this field
    }
  ]
end
```
