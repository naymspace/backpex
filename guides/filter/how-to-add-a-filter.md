# How to add a Filter?

Adding a filter to your *LiveResource* is a two step process:

## Defining a Filter module

First, you need to define a filter module that implements one of the behaviors from the `Backpex.Filters` namespace., This may be one of the [built-in filters](what-is-a-filter.md#built-in-filters) or a [custom filter](custom-filter.md).

We suggest to use a `MyAppWeb.Filters.<FILTERNAME>` convention.

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

## Adding the Filter to your LiveResource

After you have defined the filter module, you need to add the filter to your *LiveResource*.

To do this, you need to define the filter in the [filters/0](Backpex.LiveResource.html#c:filters/0) callback in your *LiveResource* module.

Here is an example of how to add a filter to your *LiveResource*:

```elixir
@impl Backpex.LiveResource
def filters, do: [
    category_id: %{
        module: MyAppWeb.Filters.PostCategorySelect,
    }
]
```

In this example, we add a filter with the name `category_id` to the *LiveResource*. The filter uses the `MyAppWeb.Filters.PostCategorySelect` module we defined earlier.

## Overwriting the Filter Label

You can also overwrite the filter label defined in the filter label by adding a `label` key to the filter map:

```elixir
@impl Backpex.LiveResource
def filters, do: [
    category_id: %{
        module: MyAppWeb.Filters.PostCategorySelect,
        label: "Category"
    }
]
```
