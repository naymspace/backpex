# Custom Filter

Backpex ships with a set of default filters that can be used to filter the data. In addition to the default filters, you can create custom filters for more advanced use cases.

## Creating a Custom Filter

You can create a custom filter by using the `filter` macro from the `BackpexWeb` module. It automatically implements the `Backpex.Filter` behavior and defines some aliases and imports.

### Required Callbacks

When creating a custom filter, you need to implement the following callbacks:

| Callback | Purpose |
|----------|---------|
| `label/0` | Returns the display label for the filter |
| `type/1` | Specifies the Ecto type for casting URL parameters |
| `query/4` | Applies the filter to the database query |
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

## The `query/4` Callback

The `query/4` function receives **already validated and casted values**. You don't need to parse strings or handle invalid input - validation happens before this callback is called.

```elixir
@impl Backpex.Filter
def query(query, attribute, value, _assigns) do
  # value is already the correct type!
  where(query, [x], field(x, ^attribute) == ^value)
end
```

## Example: Custom Select Filter

Here is an example of a custom select filter with validation:

```elixir
defmodule MyApp.Filters.EventStatusFilter do
  use BackpexWeb, :filter

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
  def query(query, attribute, value, _assigns) do
    where(query, [x], field(x, ^attribute) == ^value)
  end

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

  import Ecto.Query

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
  def query(query, attribute, value, _assigns) do
    # value is already an integer!
    where(query, [x], field(x, ^attribute) >= ^value)
  end
end
```

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
