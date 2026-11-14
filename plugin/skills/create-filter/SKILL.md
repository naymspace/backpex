---
name: create-filter
description: Use when adding a filter to a Backpex LiveResource, creating a filter module, or the user asks about filtering data in Backpex index views.
---

# Creating Backpex Filters

Filters are configured in the LiveResource's `filters/0` callback, like fields: a map names a built-in filter module and its options. A filter needs no module of its own.

When the user wants to add a filter:

1. Pick the built-in filter from the quick reference and configure it in `filters/0`
2. To change which items it keeps, pass the `:condition` option
3. Write a filter module only to reuse a filter in several LiveResources, or for a custom filter with its own form

## Quick Reference

| Module | Use for | Options |
|--------|---------|---------|
| `Backpex.Filters.Boolean` | Checkboxes, one predicate each (published yes/no) | `options:` (required), a list of `%{label, key, predicate}` maps or a function that receives the assigns |
| `Backpex.Filters.Select` | Single-value dropdown | `options:` (required), a list of `{label, value}` tuples or a function that receives the assigns; `prompt:` |
| `Backpex.Filters.MultiSelect` | Multi-value dropdown with checkboxes | `options:` (required) and `prompt:`, as for Select |
| `Backpex.Filters.Range` | Date, datetime, or number ranges | `type:` (required): `:date`, `:datetime` or `:number` |
| Custom module | Anything else | Its own `:config_schema`, see Custom Filter |

Every filter also takes these options:

| Key | Required | Description |
|-----|----------|-------------|
| `:module` | yes | The filter module |
| `:label` | yes, unless the module implements `label/0` | The filter label |
| `:default` | no | Value of the filter when the index view is opened without filters |
| `:presets` | no | Quick-select shortcuts: `[%{label: String.t(), values: (-> value)}]` |
| `:can?` | no | Function that receives the assigns and returns whether the filter is shown and applied |
| `:condition` | no | Function that returns the expression of the items the filter keeps, instead of the one of the module |

Backpex validates the options when it renders the index view and raises for an unknown or invalid option.

## Configuring Filters in a LiveResource

`filters/0` returns a keyword list. Each key is the name of the filter, the field it filters by.

```elixir
# in the LiveResource; needed for expr/1 in predicates and conditions
import Backpex.Expr, only: [expr: 1]

@impl Backpex.LiveResource
def filters do
  [
    published: %{
      module: Backpex.Filters.Boolean,
      label: "Published?",
      options: [
        %{label: "Published", key: "published", predicate: expr(published == true)},
        %{label: "Not published", key: "not_published", predicate: expr(published == false)}
      ],
      default: ["published"]
    },
    category_id: %{
      module: Backpex.Filters.Select,
      label: "Category",
      prompt: "Select category ...",
      options: &category_options/1
    },
    user_id: %{
      module: Backpex.Filters.MultiSelect,
      label: "Users",
      prompt: "Select users ...",
      options: fn _assigns -> MyApp.Accounts.list_user_options() end
    },
    likes: %{
      module: Backpex.Filters.Range,
      label: "Likes",
      type: :number,
      presets: [
        %{label: "Over 100", values: fn -> %{"start" => 100, "end" => nil} end},
        %{label: "1-99", values: fn -> %{"start" => 1, "end" => 99} end}
      ]
    }
  ]
end

defp category_options(_assigns) do
  MyApp.Blog.list_categories() |> Enum.map(&{&1.name, &1.id})
end
```

- **Boolean**: the selected options are combined with OR; with none selected the filter keeps all items.
- **Select** keeps the items whose field equals the selected value, **MultiSelect** those whose field has one of the selected values.
- **Range** renders "From" and "To" inputs and keeps the items whose field is within the range.

## Expressions

Filters don't build queries. A predicate or condition is an expression built with `Backpex.Expr.expr/1` that the adapter turns into a query. `use Backpex.Filter` and the built-in filters import `expr/1` into filter modules; a LiveResource imports it itself.

- Comparisons: `expr(ref(^field) == ^value)`, also `!=`, `<`, `<=`, `>`, `>=`; `ref(^field)` is the filtered field, `^` pins Elixir values, a bare name is another field (`expr(status == "open")`)
- `in`, `is_nil/1`, `not`, `and`, `or`: `expr(ref(^field) in ^values or is_nil(ref(^field)))`
- Strings: `contains/2`, `starts_with/2`, `ends_with/2`, with `ignore_case: true` as third argument
- Related items: a path through to-one relationships (`expr(author.name == ^name)`), `exists/2` for to-many (`expr(exists(tags, id in ^ids))`)
- `Backpex.Expr.all/1` and `any/1` combine expressions and drop `nil`; a keyword list such as `[published: true]` stands for equal fields

The adapter casts values to the type of the field. `Backpex.Expr.native(Backpex.Adapters.Ecto, dynamic(...))` wraps an expression only the Ecto adapter understands.

## Changing the Condition

To change which items a single filter keeps, pass a function to `:condition`. It receives the filter as a `{name, config}` tuple, the validated value and the assigns, and returns an expression, or `nil` to keep all items.

```elixir
age: %{
  module: Backpex.Filters.Select,
  label: "Age",
  options: [{"Under 18", "minor"}, {"18 and older", "adult"}],
  condition: fn
    {field, _config}, "minor", _assigns -> expr(ref(^field) < 18)
    {field, _config}, "adult", _assigns -> expr(ref(^field) >= 18)
  end
}
```

## Reusable Filter Modules

Define a module only when several LiveResources use the same filter. The callbacks of the built-in filters provide the defaults of their options; the options in `filters/0` take precedence.

| `use` module | Callbacks |
|--------------|-----------|
| `Backpex.Filters.Boolean` | `options/1` (`@impl Backpex.Filters.Boolean`) |
| `Backpex.Filters.Select` | `options/1`, `prompt/0` (`@impl Backpex.Filters.Select`) |
| `Backpex.Filters.MultiSelect` | `options/1`, `prompt/0` (`@impl Backpex.Filters.Select`) |
| `Backpex.Filters.Range` | `type/0` (`@impl Backpex.Filters.Range`), arity 0, not `type/2` of `Backpex.Filter` |

All of them may implement `label/0` and `can?/1` (`@impl Backpex.Filter`).

```elixir
defmodule MyAppWeb.Filters.CategorySelect do
  use Backpex.Filters.Select

  @impl Backpex.Filter
  def label, do: "Category"

  @impl Backpex.Filters.Select
  def prompt, do: "Select category ..."

  @impl Backpex.Filters.Select
  def options(_assigns) do
    MyApp.Blog.list_categories() |> Enum.map(&{&1.name, &1.id})
  end
end
```

```elixir
# in filters/0
category_id: %{module: MyAppWeb.Filters.CategorySelect, label: "Post category"}
```

## Custom Filter

Write a custom filter when no built-in filter fits, e.g. for another form. `use BackpexWeb, :filter` brings `Phoenix.Component` (`~H`) and the form helpers, `use Backpex.Filter` the behaviour with default callbacks and `expr/1`.

The callbacks receive the filter as a `{name, config}` tuple, where `config` is the validated map of its options. `render/1` and `render_form/1` find it in `@filter`, next to `@field`, `@value` and, in `render_form/1`, `@form`.

| Callback | Required | Purpose |
|----------|----------|---------|
| `condition/3` | yes | `(filter, value, assigns)`: the expression of the items the filter keeps, `nil` keeps all. The value is already validated and cast |
| `render/1` | yes | Renders the value in the filter badge |
| `render_form/1` | yes | Renders the filter input |
| `type/2` | no | `(filter, assigns)`: Ecto type the value is cast to, default `:string` |
| `changeset/3` | no | `(changeset, filter, assigns)`: custom validation, default: no-op |
| `validate/3` | no | `(filter, value, assigns)`: validation API for tests, built from `type/2` and `changeset/3` |
| `label/0` | no | Label if the filter has no `:label` option |
| `can?/1` | no | Receives the assigns, default `true` |

`type/1`, `validate/2` and `query/4` of earlier versions are gone: a filter module that defines one of them does not compile.

Options of the filter are a NimbleOptions schema passed as `:config_schema`.

```elixir
defmodule MyAppWeb.Filters.MinQuantity do
  use BackpexWeb, :filter

  use Backpex.Filter,
    config_schema: [
      max: [doc: "The largest quantity.", type: :integer, default: 10_000]
    ]

  @impl Backpex.Filter
  def label, do: "Minimum quantity"

  @impl Backpex.Filter
  def type(_filter, _assigns), do: :integer

  @impl Backpex.Filter
  def changeset(changeset, {field, config}, _assigns) do
    Ecto.Changeset.validate_number(changeset, field,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: config.max
    )
  end

  @impl Backpex.Filter
  def condition({field, _config}, value, _assigns), do: expr(ref(^field) >= ^value)

  @impl Backpex.Filter
  def render(assigns) do
    ~H"""
    &ge; {@value}
    """
  end

  @impl Backpex.Filter
  def render_form(assigns) do
    {_name, config} = assigns.filter
    assigns = assign(assigns, :max, config.max)

    ~H"""
    <input type="number" name={@form[@field].name} value={@value} min="0" max={@max} class="input input-sm" />
    """
  end
end
```

```elixir
# in filters/0
quantity: %{module: MyAppWeb.Filters.MinQuantity, max: 500}
```

### Related items and Ecto-only expressions

A filter never joins, selects distinct items or otherwise changes the query; the adapter owns joins, order and pagination. To filter by an association (e.g. posts with one of the selected tags), use `exists/2`:

```elixir
@impl Backpex.Filter
def condition(_filter, tag_ids, _assigns), do: expr(exists(tags, id in ^tag_ids))
```

If a filter needs a fragment of SQL, wrap an `Ecto.Query.dynamic/2` expression with `Backpex.Expr.native/2`. The filter then only works with `Backpex.Adapters.Ecto`.

```elixir
import Ecto.Query

@impl Backpex.Filter
def condition({field, _config}, value, _assigns) do
  Backpex.Expr.native(Backpex.Adapters.Ecto, dynamic([x], fragment("lower(?)", field(x, ^field)) == ^value))
end
```

## Conventions

- **Configure first**: a built-in filter with options in `filters/0`; a module only for reuse or a custom form
- **The keyword list key** in `filters/0` must match the database column or foreign key
- **Module naming**: `MyAppWeb.Filters.<FilterName>` (e.g. `MyAppWeb.Filters.CategorySelect`)
- **File location**: `lib/my_app_web/filters/<snake_case_name>.ex`
- **Prefer `expr/1`** over native Ecto expressions; expressions work with every adapter
- **Database queries in `:options` functions and `options/1`** are fine since they run at render time
