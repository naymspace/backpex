# How to add a Filter?

Filters are configured in your *LiveResource*, just like fields. You don't need a module per filter.

## Adding a Filter to your LiveResource

Define the filters in the [filters/0](Backpex.LiveResource.html#c:filters/0) callback of your *LiveResource*. Each filter has a name, the field it filters by, and a map with the filter module and its options:

```elixir
@impl Backpex.LiveResource
def filters do
  [
    category_id: %{
      module: Backpex.Filters.Select,
      label: "Category",
      prompt: "Select category ...",
      options: &category_options/1
    },
    likes: %{
      module: Backpex.Filters.Range,
      label: "Likes",
      type: :number
    }
  ]
end

defp category_options(_assigns) do
  MyApp.Blog.list_categories()
  |> Enum.map(&{&1.name, &1.id})
end
```

In this example, we add a select filter with the name `category_id` and a range filter with the name `likes` to the *LiveResource*.

The `:module` may be one of the [built-in filters](what-is-a-filter.md#built-in-filters) or a [custom filter](custom-filter.md). Click on a built-in filter to see its options. The options every filter takes, such as `:label`, `:default`, `:presets`, `:can?` and `:condition`, are listed in `Backpex.Filter`.

Backpex validates the options when it renders the index view and raises an error for an unknown or invalid option.

When you use built-in filters like `Backpex.Filters.Select`, validation is handled automatically: the filter validates that the selected values exist in the options list.

## Default Values

The `:default` option sets the value of a filter when the index view is opened without filters:

```elixir
published: %{
  module: Backpex.Filters.Boolean,
  label: "Published?",
  options: [
    %{label: "Published", key: "published", predicate: {:==, :published, true}},
    %{label: "Not published", key: "not_published", predicate: {:==, :published, false}}
  ],
  default: ["published"]
}
```

## Changing the Condition

A filter keeps the items that match its condition, see the Conditions section of `Backpex.Filter`. To change the condition of a single filter, pass a function to the `:condition` option. It receives the filter, the validated value and the assigns:

```elixir
age: %{
  module: Backpex.Filters.Select,
  label: "Age",
  options: [{"Under 18", "minor"}, {"18 and older", "adult"}],
  condition: fn
    {field, _config}, "minor", _assigns -> {:<, field, 18}
    {field, _config}, "adult", _assigns -> {:>=, field, 18}
  end
}
```

## Reusable Filter Modules

If you use the same filter in several *LiveResources*, you can define a module for it. The built-in filters have callbacks that provide the defaults of their options. We suggest using a `MyAppWeb.Filters.<FILTERNAME>` convention.

```elixir
defmodule MyAppWeb.Filters.CategorySelect do
  use Backpex.Filters.Select

  @impl Backpex.Filter
  def label, do: "Category"

  @impl Backpex.Filters.Select
  def prompt, do: "Select category ..."

  @impl Backpex.Filters.Select
  def options(_assigns) do
    MyApp.Blog.list_categories()
    |> Enum.map(&{&1.name, &1.id})
  end
end
```

Use the module as the `:module` of a filter. The options of the filter take precedence over the callbacks of the module:

```elixir
@impl Backpex.LiveResource
def filters do
  [
    category_id: %{
      module: MyAppWeb.Filters.CategorySelect,
      label: "Post category"
    }
  ]
end
```

## Filter Validation

Built-in filters automatically validate their values. For custom filters, you can add validation via the `changeset/3` callback. See the [Filter Validation Guide](filter-validation.md) for details.

## Related Guides

- [What is a Filter?](what-is-a-filter.md) - Overview of the filter system
- [Custom Filters](custom-filter.md) - Creating custom filter types
- [Filter Validation](filter-validation.md) - Comprehensive validation documentation
- [Filter Presets](filter-presets.md) - Pre-configured filter combinations
- [Visibility and Authorization](visibility-and-authorization.md) - Controlling filter access
