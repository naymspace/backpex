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

## NULL Values

By default, Backpex leaves the placement of `NULL` values to the database. PostgreSQL treats `NULL` as larger than any
other value, so `NULL` values come last in ascending and first in descending order. This matches a regular index,
which lets the database read the page from the index instead of sorting the whole table.

Use the `order_nulls` option to change this for all fields of a LiveResource:

```elixir
use Backpex.LiveResource,
  # ...other options
  order_nulls: :last
```

Or for a single field, which overrides the LiveResource option:

```elixir
published_at: %{
  module: Backpex.Fields.DateTime,
  label: "Published at",
  order_nulls: :last
}
```

The option accepts:

- `:default` - The database default (`ORDER BY published_at ASC` or `DESC`)
- `:first` - `NULL` values first in both directions (`NULLS FIRST`)
- `:last` - `NULL` values last in both directions (`NULLS LAST`)

Ordering by the LiveResource's `primary_key` always uses the database default, because a primary key is never `NULL`.
This includes the default `init_order`.

> #### Indexes for `:first` and `:last` {: .warning}
>
> A regular index can't serve `NULLS FIRST` in ascending or `NULLS LAST` in descending order. Without a matching index,
> the database sorts the whole table on every page load, which gets slow and writes temporary files on large tables
> (especially on later pages). Create an index for each order you use. An index can be read backwards, so one index
> serves one order and its exact reverse:
>
> ```elixir
> # ASC NULLS LAST and DESC NULLS FIRST (order_nulls: :default)
> create index(:posts, [:published_at])
>
> # ASC NULLS FIRST and DESC NULLS LAST
> create index(:posts, ["published_at NULLS FIRST"])
>
> # DESC NULLS FIRST and ASC NULLS LAST
> create index(:posts, ["published_at DESC NULLS FIRST"])
> ```
>
> `order_nulls: :first` needs the second index for ascending and the third for descending order. `:last` needs the same
> two the other way round.

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
