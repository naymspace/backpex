# Context Assigns

Callbacks that are called while the index table is rendered receive the assigns of the LiveView, for example `c:Backpex.LiveResource.can?/3`, `c:Backpex.LiveResource.index_row_class/4`, the callbacks of item actions and the functions and callbacks of fields in each cell.

By default, Backpex passes all assigns. LiveView cannot know which of them the table actually uses, so it re-renders every row and every field component of the table whenever any assign of the LiveView changes, even one that is only used outside of the table, like the visibility of the metrics or an assign of your own `render_resource_slot/3`.

## Configure LiveResource

Set the `context_assigns` option to the assigns your callbacks need in addition to the ones Backpex always passes (`:live_resource`, `:live_action`, `:params`, `:fields`, `:item_actions` and a `:socket` for building routes):

```elixir
# in your LiveResource module
defmodule MyAppWeb.Live.UserLive do
  use Backpex.LiveResource,
    ...,
    context_assigns: [:current_scope]
end
```

The table is then only re-rendered when its data or one of these assigns changes.

> #### Warning {: .warning}
>
> Callbacks rendered in the index table no longer see any other assign. Add every assign that your `can?/3`, `index_row_class/4`, item actions and fields read to `context_assigns`. The `:socket` only carries the router and endpoint, so use `:all` if your callbacks need anything else from it.

Functions that do not run while rendering, like the `item_query` of the adapter config or the queries of filters, still receive all assigns.
