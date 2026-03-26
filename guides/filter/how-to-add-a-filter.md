# How to add a Filter?

Adding a filter to your *LiveResource* is a two step process:

## Defining a Filter module

First, you need to define a filter module that implements one of the behaviors from the `Backpex.Filters` namespace. This may be one of the [built-in filters](what-is-a-filter.md#built-in-filters) or a [custom filter](custom-filter.md).

We suggest using a `MyAppWeb.Filters.<FILTERNAME>` convention.

If you want to add one of the built-in filters, you can click on the filter type in the list of [Built-in Filters](what-is-a-filter.md#built-in-filters) to see how to define a filter module for that filter type.

For example, the following example shows how to define a filter module for a select filter that filters posts based on a category:

```elixir
defmodule MyAppWeb.Filters.PostCategorySelect do
  use Backpex.Filters.Select

  alias MyApp.Category
  alias MyApp.Post
  alias MyApp.Repo

  @impl Backpex.Filter
  def label, do: "Category"

  @impl Backpex.Filters.Select
  def prompt, do: "Select category ..."

  @impl Backpex.Filters.Select
  def options(_assigns) do
    query =
      from p in Post,
        join: c in Category,
        on: p.category_id == c.id,
        distinct: c.name,
        select: {c.name, c.id}

    Repo.all(query)
  end
end
```

When using built-in filters like `Backpex.Filters.Select`, validation is handled automatically - the filter validates that selected values exist in the options list.

## Adding the Filter to your LiveResource

After you have defined the filter module, you need to add the filter to your *LiveResource*.

To do this, you need to define the filter in the [filters/0](Backpex.LiveResource.html#c:filters/0) callback in your *LiveResource* module.

Here is an example of how to add a filter to your *LiveResource*:

```elixir
@impl Backpex.LiveResource
def filters, do: [
  category_id: %{
    module: MyAppWeb.Filters.PostCategorySelect
  }
]
```

In this example, we add a filter with the name `category_id` to the *LiveResource*. The filter uses the `MyAppWeb.Filters.PostCategorySelect` module we defined earlier.

## Overwriting the Filter Label

You can overwrite the filter label defined in the filter module by adding a `label` key to the filter map:

```elixir
@impl Backpex.LiveResource
def filters, do: [
  category_id: %{
    module: MyAppWeb.Filters.PostCategorySelect,
    label: "Category"
  }
]
```

## Filter Validation

Built-in filters automatically validate their values. For custom filters, you can add validation via the `changeset/3` callback. See the [Filter Validation Guide](filter-validation.md) for details.

## Related Guides

- [What is a Filter?](what-is-a-filter.md) - Overview of the filter system
- [Custom Filters](custom-filter.md) - Creating custom filter types
- [Filter Validation](filter-validation.md) - Comprehensive validation documentation
- [Filter Presets](filter-presets.md) - Pre-configured filter combinations
- [Visibility and Authorization](visibility-and-authorization.md) - Controlling filter access
