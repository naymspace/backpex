# Visibility and Authorization

You can control whether a filter is visible or not with the `:can?` option of the filter or the [can?/1](Backpex.Filter.html#c:can?/1) callback of the filter module. A hidden filter is neither shown nor applied.

## The `:can?` Option

The `:can?` option takes a function that receives the assigns and has to return a boolean value. If the function returns `true`, the filter will be visible. If it returns `false`, the filter will be hidden.

Here is an example of how to hide a filter based on the user's role:

```elixir
@impl Backpex.LiveResource
def filters do
  [
    user_id: %{
      module: Backpex.Filters.Select,
      label: "User",
      options: &user_options/1,
      can?: fn assigns -> assigns.current_user.role == :admin end
    }
  ]
end
```

In this example, the `user_id` filter will only be visible if the user's role is `admin`.

## The `can?/1` Callback

A filter module can implement the [can?/1](Backpex.Filter.html#c:can?/1) callback to hide the filter wherever it is used. It also receives the assigns and has to return a boolean value. If you don't implement the `can?/1` callback, the filter will be visible by default.

```elixir
defmodule MyAppWeb.Filters.UserSelect do
  use Backpex.Filters.Select

  @impl Backpex.Filter
  def can?(assigns), do: assigns.current_user.role == :admin

  # ...the callbacks of `Backpex.Filters.Select`
end
```

A filter with both is only visible if the `:can?` option and the `can?/1` callback return `true`.
