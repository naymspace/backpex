# Filter Validation

Backpex filters support changeset-based validation to ensure that URL parameters are validated before being applied to database queries. This provides type safety, prevents crashes from malformed data, and enables user-friendly error messages.

## How Validation Works

When a user applies a filter (via the UI or URL parameters), Backpex:

1. **Builds a Changeset**: Creates an Ecto schemaless changeset from the URL parameters
2. **Casts Values**: Converts string values to the appropriate types based on `type/1`
3. **Runs Validations**: Applies any custom validations defined in `changeset/3`
4. **Extracts Valid Values**: Only filters that pass validation are applied to the query
5. **Shows Errors**: Invalid filters display inline validation errors in the UI

Invalid filters are **not applied** to the query - the user sees unfiltered results for that attribute while the error is displayed.

## The `type/1` Callback

The `type/1` callback specifies the Ecto type for your filter's value. This is used for casting URL string parameters to the correct type.

```elixir
@impl Backpex.Filter
def type(_assigns), do: :string
```

### Common Types

| Type | Use Case | Example Values |
|------|----------|----------------|
| `:string` | Single value select/text filters | `"active"`, `"pending"` |
| `{:array, :string}` | Multi-select, boolean (checkbox) filters | `["a", "b"]` |
| `:map` | Range filters with start/end | `%{"start" => "1", "end" => "100"}` |
| `:integer` | Numeric filters (whole numbers) | `42` |
| `:float` | Numeric filters (decimals) | `3.14` |

### Type Examples

**Select filter (single value):**
```elixir
def type(_assigns), do: :string
```

**Boolean filter (multiple checkboxes):**
```elixir
def type(_assigns), do: {:array, :string}
```

**Range filter:**
```elixir
def type(_assigns), do: :map
```

**Numeric filter:**
```elixir
def type(_assigns), do: :integer
```

## The `changeset/3` Callback

The `changeset/3` callback allows you to add custom validations to your filter. It receives the changeset being built, the field atom, and assigns.

```elixir
@impl Backpex.Filter
def changeset(changeset, field, _assigns) do
  changeset
  |> Ecto.Changeset.validate_number(field, greater_than: 0, less_than: 1000)
end
```

### Default Implementation

If you don't implement `changeset/3`, the default implementation returns the changeset unchanged. Type casting still occurs based on `type/1`.

### Validation Examples

**Validate numeric range:**
```elixir
def changeset(changeset, field, _assigns) do
  Ecto.Changeset.validate_number(changeset, field,
    greater_than_or_equal_to: 0,
    less_than_or_equal_to: 100
  )
end
```

**Validate allowed values:**
```elixir
def changeset(changeset, field, _assigns) do
  Ecto.Changeset.validate_inclusion(changeset, field, ["active", "pending", "closed"])
end
```

**Validate format:**
```elixir
def changeset(changeset, field, _assigns) do
  Ecto.Changeset.validate_format(changeset, field, ~r/^[A-Z]{2,3}-\d+$/)
end
```

**Validate based on options (for select filters):**
```elixir
def changeset(changeset, field, assigns) do
  valid_values = Enum.map(options(assigns), fn {_label, value} -> to_string(value) end)

  Ecto.Changeset.validate_inclusion(changeset, field, valid_values)
end
```

## Built-in Filter Validation

The built-in filters automatically validate their values:

### Boolean Filter

Validates that all selected checkbox keys exist in the `options/1` list.

```elixir
# If options returns:
[
  %{label: "Published", key: "published", predicate: ...},
  %{label: "Draft", key: "draft", predicate: ...}
]

# Valid: ["published"], ["draft"], ["published", "draft"]
# Invalid: ["unknown_key"]
```

### Select Filter

Validates that the selected value exists in the `options/1` list.

```elixir
# If options returns:
[{"Active", "active"}, {"Inactive", "inactive"}]

# Valid: "active", "inactive"
# Invalid: "unknown"
```

### MultiSelect Filter

Validates that all selected values exist in the `options/1` list.

```elixir
# If options returns:
[{"John", "user-1"}, {"Jane", "user-2"}]

# Valid: ["user-1"], ["user-1", "user-2"]
# Invalid: ["user-1", "invalid-uuid"]
```

### Range Filter

Validates based on the range type:

**Number ranges:**
- Values must be valid integers or floats
- Start must be less than or equal to end (when both provided)

**Date ranges:**
- Values must be valid ISO 8601 dates (YYYY-MM-DD)
- Start date must be on or before end date (when both provided)

**Datetime ranges:**
- Values must be valid ISO 8601 dates
- Start must be on or before end
- Time boundaries are automatically added (00:00:00 for start, 23:59:59 for end)

## The `validate/2` Callback

The `validate/2` callback provides a public API for programmatic validation and testing:

```elixir
@impl Backpex.Filter
def validate(value, assigns) do
  # Returns {:ok, casted_value} or {:error, errors}
end
```

The default implementation builds a mini-changeset and validates it using `type/1` and `changeset/3`. You typically don't need to override this.

### Testing Validation

```elixir
defmodule MyFilterTest do
  use ExUnit.Case

  alias MyApp.Filters.StatusFilter

  test "validates allowed values" do
    assert {:ok, "active"} = StatusFilter.validate("active", %{})
    assert {:error, _} = StatusFilter.validate("invalid", %{})
  end

  test "validates numeric ranges" do
    assert {:ok, 50} = MyApp.Filters.AmountFilter.validate("50", %{})
    assert {:error, _} = MyApp.Filters.AmountFilter.validate("-10", %{})
  end
end
```

## Query Receives Validated Values

The `query/4` callback receives already-validated and casted values:

```elixir
def query(query, attribute, value, _assigns) do
  # value is already an integer
  where(query, [x], field(x, ^attribute) == ^value)
end
```

## Complete Custom Filter Example

Here's a complete example of a custom filter with validation:

```elixir
defmodule MyAppWeb.Filters.PriceRange do
  use BackpexWeb, :filter

  import Ecto.Query

  @impl Backpex.Filter
  def label, do: "Price Range"

  @impl Backpex.Filter
  def type(_assigns), do: :map

  @impl Backpex.Filter
  def changeset(changeset, field, _assigns) do
    Ecto.Changeset.validate_change(changeset, field, fn _field, value ->
      validate_price_range(value, field)
    end)
  end

  defp validate_price_range(%{"min" => min_str, "max" => max_str}, field) do
    errors = []

    min = parse_price(min_str)
    max = parse_price(max_str)

    errors = if min_str != "" and is_nil(min) do
      [{field, "minimum price is invalid"}]
    else
      errors
    end

    errors = if max_str != "" and is_nil(max) do
      [{field, "maximum price is invalid"} | errors]
    else
      errors
    end

    errors = if min && max && min > max do
      [{field, "minimum cannot exceed maximum"} | errors]
    else
      errors
    end

    errors
  end

  defp validate_price_range(_value, _field), do: []

  defp parse_price(""), do: nil
  defp parse_price(str) do
    case Float.parse(str) do
      {value, ""} when value >= 0 -> value
      _ -> nil
    end
  end

  @impl Backpex.Filter
  def query(query, attribute, %{"min" => min, "max" => max}, _assigns) do
    query
    |> maybe_filter_min(attribute, parse_price(min))
    |> maybe_filter_max(attribute, parse_price(max))
  end

  def query(query, _attribute, _value, _assigns), do: query

  defp maybe_filter_min(query, _attr, nil), do: query
  defp maybe_filter_min(query, attr, min), do: where(query, [x], field(x, ^attr) >= ^min)

  defp maybe_filter_max(query, _attr, nil), do: query
  defp maybe_filter_max(query, attr, max), do: where(query, [x], field(x, ^attr) <= ^max)

  @impl Backpex.Filter
  def render(assigns) do
    min = assigns.value["min"]
    max = assigns.value["max"]

    ~H"""
    <span :if={@value["max"] == ""}>&ge; <%= min %></span>
    <span :if={@value["min"] == ""}>&le; <%= max %></span>
    <span :if={@value["min"] != "" and @value["max"] != ""}><%= min %> &mdash; <%= max %></span>
    """
  end

  @impl Backpex.Filter
  def render_form(assigns) do
    ~H"""
    <div class="mt-2 space-y-2">
      <label class={["input input-sm", @errors != [] && "input-error bg-error/10"]}>
        <span class="text-base-content/50">Min</span>
        <input
          type="number"
          name={@form[@field].name <> "[min]"}
          value={@value["min"]}
          min="0"
          step="0.01"
        />
      </label>
      <label class={["input input-sm", @errors != [] && "input-error bg-error/10"]}>
        <span class="text-base-content/50">Max</span>
        <input
          type="number"
          name={@form[@field].name <> "[max]"}
          value={@value["max"]}
          min="0"
          step="0.01"
        />
      </label>
    </div>
    <.error :for={msg <- @errors} class="mt-1">{msg}</.error>
    """
  end
end
```

## Error Display

When validation fails, the filter shows an error state in the UI:

1. The filter input shows an error border/styling
2. An error message appears below the input
3. The filter badge does **not** appear (filter is not applied)
4. Results show unfiltered data for that attribute

This provides immediate feedback while keeping the application stable.

### Displaying Errors in Custom Filters

The `@errors` assign is passed to your filter's `render_form/1` callback, containing a list of translated error messages. Built-in filters automatically display these errors with appropriate styling. For custom filters, you can display errors using the `.error` component (available via `use BackpexWeb, :filter`):

```elixir
@impl Backpex.Filter
def render_form(assigns) do
  ~H"""
  <input
    type="text"
    name={@form[@field].name}
    value={@value}
    class={["input input-sm mt-2", @errors != [] && "input-error bg-error/10"]}
  />
  <.error :for={msg <- @errors} class="mt-1">{msg}</.error>
  """
end
```

## Best Practices

1. **Always implement `type/1`**: Even if using the default `:string`, be explicit
2. **Validate against options**: For select/multi-select filters, validate values exist in your options list
3. **Handle partial values**: For range filters, allow empty start or end values
4. **Keep `query/4` simple**: Since values are validated, focus on the query logic
5. **Test validation**: Write unit tests for your `validate/2` to ensure edge cases are handled
6. **Use Ecto validations**: Leverage `Ecto.Changeset` validation functions for consistency
7. **Display errors in custom filters**: Use `@errors` in `render_form/1` to show validation feedback to users
