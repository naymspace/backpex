---
name: create-filter
description: Use when adding a filter to a Backpex LiveResource, creating a filter module, or the user asks about filtering data in Backpex index views.
---

# Creating Backpex Filters

When the user wants to add a filter:

1. Pick the right filter type from the quick reference
2. Generate the filter module
3. Wire it into the LiveResource's `filters/0` callback

## Quick Reference

| Type | Use for | `use` module | Key callbacks |
|------|---------|-------------|---------------|
| Boolean | Checkbox predicates (published yes/no) | `Backpex.Filters.Boolean` | `options/1` returning `%{label, key, predicate}` maps |
| Select | Single-value dropdown | `Backpex.Filters.Select` | `prompt/0`, `options/1` returning `{label, value}` tuples |
| MultiSelect | Multi-value dropdown with checkboxes | `Backpex.Filters.MultiSelect` | `prompt/0`, `options/1` returning `{label, value}` tuples |
| Range | Date, datetime, or number ranges | `Backpex.Filters.Range` | `type/0` returning `:date`, `:datetime`, or `:number` |
| Custom | Anything else | `Backpex.Filter` | `query/4`, `render/1`, `render_form/1` |

All built-in filters auto-implement `query/4`, `render/1`, and `render_form/1`. Do NOT re-implement those unless you need custom behavior.

All filters have these overridable callbacks with defaults:
- `label/0`: filter label (optional callback, can also be set in `filters/0` map)
- `can?/1`: visibility control, receives assigns, default `true`
- `type/1`: Ecto type for validation (default `:string`), receives assigns
- `changeset/3`: custom changeset validation (default: no-op)
- `validate/2`: public validation API, builds changeset from `type/1` and `changeset/3`

## Boolean Filter

Multiple options selectable via checkboxes, combined with OR. Predicates use `Ecto.Query.dynamic/2`.

```elixir
defmodule MyAppWeb.Filters.PostPublished do
  use Backpex.Filters.Boolean

  import Ecto.Query

  @impl Backpex.Filter
  def label, do: "Published?"

  @impl Backpex.Filters.Boolean
  def options(_assigns) do
    [
      %{label: "Published", key: "published", predicate: dynamic([x], x.published)},
      %{label: "Not published", key: "not_published", predicate: dynamic([x], not x.published)}
    ]
  end
end
```

## Select Filter

Single-value dropdown. Default `query/4` does `WHERE field = value`.

```elixir
defmodule MyAppWeb.Filters.PostCategorySelect do
  use Backpex.Filters.Select

  import Ecto.Query

  alias MyApp.Repo

  @impl Backpex.Filter
  def label, do: "Category"

  @impl Backpex.Filters.Select
  def prompt, do: "Select category ..."

  @impl Backpex.Filters.Select
  def options(_assigns) do
    from(c in MyApp.Category, select: {c.name, c.id}, order_by: c.name) |> Repo.all()
  end
end
```

## MultiSelect Filter

Same as Select but allows multiple values. Default `query/4` does `WHERE field IN values`. Uses `prompt/0` (implement with `@impl Backpex.Filters.Select`) and `options/1` (implement with `@impl Backpex.Filters.MultiSelect`). Note: MultiSelect internally sets `@behaviour Backpex.Filters.Select` for the prompt callback.

## Range Filter

Renders "From" and "To" inputs. Note: `type/0` is arity 0, not arity 1.

```elixir
defmodule MyAppWeb.Filters.PostLikeRange do
  use Backpex.Filters.Range

  @impl Backpex.Filters.Range
  def type, do: :number

  @impl Backpex.Filter
  def label, do: "Likes"
end
```

For dates use `def type, do: :date`. For datetimes use `def type, do: :datetime`.

## Custom Filter

Use `Backpex.Filter` directly when no built-in type fits. You must implement `query/4`, `render/1`, and `render_form/1`. Note: `use Backpex.Filter` does not import HEEx sigils. You need `use Phoenix.Component` for `~H` support.

```elixir
defmodule MyAppWeb.Filters.PostCustom do
  use Phoenix.Component
  use Backpex.Filter

  import Ecto.Query

  @impl Backpex.Filter
  def label, do: "Custom"

  @impl Backpex.Filter
  def query(query, attribute, value, _assigns) do
    where(query, [x], field(x, ^attribute) == ^value)
  end

  @impl Backpex.Filter
  def render(assigns) do
    ~H"{@value}"
  end

  @impl Backpex.Filter
  def render_form(assigns) do
    ~H"""
    <input type="text" name={@form[@field].name} value={@value} class="input input-sm" />
    """
  end
end
```

## Wiring Into a LiveResource

`filters/0` returns a keyword list. Each key is the schema field atom being filtered.

```elixir
@impl Backpex.LiveResource
def filters do
  [
    published: %{
      module: MyAppWeb.Filters.PostPublished
    },
    category_id: %{
      module: MyAppWeb.Filters.PostCategorySelect,
      label: "Category"
    },
    likes: %{
      module: MyAppWeb.Filters.PostLikeRange,
      label: "Likes",
      presets: [
        %{label: "Over 100", values: fn -> %{"start" => 100, "end" => nil} end},
        %{label: "1-99", values: fn -> %{"start" => 1, "end" => 99} end}
      ]
    }
  ]
end
```

### Filter map keys

| Key | Required | Description |
|-----|----------|-------------|
| `:module` | yes | The filter module |
| `:label` | no | Overrides the module's `label/0` |
| `:default` | no | Pre-selected value on initial page load |
| `:presets` | no | Quick-select shortcuts: `[%{label: String.t(), values: (-> value)}]` |

## Conventions

- **Module naming**: `MyAppWeb.Filters.<Resource><FilterName>` (e.g. `MyAppWeb.Filters.PostPublished`)
- **File location**: `lib/my_app_web/filters/<snake_case_name>.ex`
- **The keyword list key** in `filters/0` must match the database column or foreign key
- **Always `import Ecto.Query`** when using `dynamic/2` or writing custom queries
- **Database queries in `options/1`** are fine since it runs at render time
