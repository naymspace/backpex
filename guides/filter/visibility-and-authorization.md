# Visibility and Authorization

You can control whether a filter is visible or not by implementing the [can?/1](Backpex.Filter.html#c:can?/1) callback in your filter module.

## Configuration

The [can?/1](Backpex.Filter.html#c:can?/1) callback receives the assigns and has to return a boolean value. If the callback returns `true`, the filter will be visible. If it returns `false`, the filter will be hidden. If you don't implement the `can?/1` callback, the filter will be visible by default.

Here is an example of how to hide a filter based on the user's role:

```elixir
defmodule MyAppWeb.Filters.MyFilter do
  use BackpexWeb, :filter

  @impl Backpex.Filter
  def can?(assigns), do: assigns.current_user.role == :admin
end
```

In this example, the `MyFilter` filter will only be visible if the user's role is `admin`.

