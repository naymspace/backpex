# Custom Filter

Backpex ships with a set of default filters that can be used to filter the data. In addition to the default filters, you can create custom filters for more advanced use cases.

## Creating a Custom Filter

You can create a custom filter by using the `filter` macro from the `BackpexWeb` module, which imports the components and helpers to render a filter, and `Backpex.Filter`, which implements the `Backpex.Filter` behavior with default callbacks.

### Required Callbacks

When creating a custom filter, you need to implement the following callbacks:

| Callback | Purpose |
|----------|---------|
| `label/0` | Returns the display label for the filter |
| `type/1` | Specifies the Ecto type for casting URL parameters |
| `condition/3` | Returns the expression of the items the filter keeps |
| `render/1` | Renders the filter badge when active |
| `render_form/1` | Renders the filter input form |

### Optional Callbacks

| Callback | Purpose |
|----------|---------|
| `changeset/3` | Adds custom validation logic |
| `can?/1` | Controls filter visibility based on assigns |

## The `type/1` Callback

The `type/1` callback specifies the Ecto type for your filter's value. This is used for casting URL string parameters to the correct type before validation and query execution.

```elixir
@impl Backpex.Filter
def type(_assigns), do: :string
```

Common types include:
- `:string` - Single value filters (select, text input)
- `{:array, :string}` - Multi-value filters (checkboxes, multi-select)
- `:map` - Range filters with start/end values
- `:integer`, `:float` - Numeric filters

## The `changeset/3` Callback

The optional `changeset/3` callback allows you to add custom validation logic. It receives the changeset, field atom, and assigns.

```elixir
@impl Backpex.Filter
def changeset(changeset, field, _assigns) do
  Ecto.Changeset.validate_inclusion(changeset, field, ["open", "closed", "pending"])
end
```

If not implemented, the default returns the changeset unchanged (type casting still occurs).

## The `condition/3` Callback

A filter doesn't query the items itself. The `condition/3` function returns an expression that describes the items the filter keeps, and the adapter of the LiveResource turns it into a query. Return `nil` to keep all items. Write the expression with `Backpex.Expr.expr/1`, which `use Backpex.Filter` imports. See `Backpex.Expr` for all operators and functions.

The function receives **already validated and casted values**. You don't need to parse strings or handle invalid input - validation happens before this callback is called.

```elixir
@impl Backpex.Filter
def condition(field, value, _assigns) do
  # value is already the correct type!
  expr(ref(^field) == ^value)
end
```

`ref(^field)` refers to the field the filter is configured for, and `^value` is the value of the filter. Expressions can combine conditions and refer to other fields, e.g. `expr(status == "open" or is_nil(closed_at))`.

## Example: Custom Select Filter

Here is an example of a custom select filter with validation:

```elixir
defmodule MyApp.Filters.EventStatusFilter do
  use BackpexWeb, :filter
  use Backpex.Filter

  @impl Backpex.Filter
  def label, do: "Event status"

  @impl Backpex.Filter
  def type(_assigns), do: :string

  @impl Backpex.Filter
  def changeset(changeset, field, _assigns) do
    valid_values = Enum.map(my_options(), fn {_label, value} -> to_string(value) end)
    Ecto.Changeset.validate_inclusion(changeset, field, valid_values)
  end

  @impl Backpex.Filter
  def render(assigns) do
    assigns = assign(assigns, :label, option_value_to_label(my_options(), assigns.value))

    ~H"""
    {@label}
    """
  end

  @impl Backpex.Filter
  def render_form(assigns) do
    ~H"""
    <.form_field
      type="select"
      selected={selected(@value)}
      options={my_options()}
      form={@form}
      field={@field}
      label=""
    />
    """
  end

  @impl Backpex.Filter
  def condition(field, value, _assigns), do: expr(ref(^field) == ^value)

  defp option_value_to_label(options, value) do
    Enum.find_value(options, fn {option_label, option_value} ->
      if to_string(option_value) == value, do: option_label
    end)
  end

  defp my_options do
    [
      {"Select an option...", ""},
      {"Open", "open"},
      {"Closed", "closed"}
    ]
  end

  defp selected(""), do: nil
  defp selected(value), do: value
end
```

## Example: Custom Numeric Filter

Here's a numeric filter that validates the value is within a specific range:

```elixir
defmodule MyApp.Filters.QuantityFilter do
  use BackpexWeb, :filter
  use Backpex.Filter

  @impl Backpex.Filter
  def label, do: "Minimum Quantity"

  @impl Backpex.Filter
  def type(_assigns), do: :integer

  @impl Backpex.Filter
  def changeset(changeset, field, _assigns) do
    Ecto.Changeset.validate_number(changeset, field,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 10000
    )
  end

  @impl Backpex.Filter
  def render(assigns) do
    ~H"""
    &ge; {@value}
    """
  end

  @impl Backpex.Filter
  def render_form(assigns) do
    ~H"""
    <input
      type="number"
      name={@form[@field].name}
      value={@value}
      min="0"
      max="10000"
      class="input input-sm"
    />
    """
  end

  @impl Backpex.Filter
  def condition(field, value, _assigns) do
    # value is already an integer!
    expr(ref(^field) >= ^value)
  end
end
```

## Related Items

An expression can refer to fields of related items. A path such as `author.name` goes through a relationship to one item, and `exists/2` keeps the items with at least one matching related item. This filter keeps the posts with one of the selected tags:

```elixir
@impl Backpex.Filter
def condition(_field, tag_ids, _assigns), do: expr(exists(tags, id in ^tag_ids))
```

A filter can't change the query itself, e.g. join a table or select distinct items, as the adapter decides how to join, order and paginate the items. `exists/2` never returns a post twice when it has two of the tags, so the filter needs no `distinct`, which would change the order of the items.

## Expressions Specific to Ecto

An expression that only `Backpex.Adapters.Ecto` understands, e.g. a fragment of SQL, is wrapped with `Backpex.Expr.native/2`. Such a filter only works with the Ecto adapter.

```elixir
defmodule MyApp.Filters.EventStatusSelect do
  use Backpex.Filters.Select

  import Ecto.Query

  # ...the callbacks of `Backpex.Filters.Select`

  @impl Backpex.Filter
  def condition(field, value, _assigns) do
    Backpex.Expr.native(Backpex.Adapters.Ecto, dynamic([event], fragment("lower(?)", field(event, ^field)) == ^value))
  end
end
```

The positional binding of the dynamic expression, `event` here, is the resource.

## Validation Behavior

When validation fails:
- The filter shows an error state in the UI
- The filter is **not** applied to the query
- Results show unfiltered data for that attribute
- The invalid value remains in the form for correction

This provides immediate feedback while keeping the application stable.

## See Also

- [Filter Validation Guide](filter-validation.md) for comprehensive validation documentation
- `Backpex.Filter` for the complete list of callback functions
