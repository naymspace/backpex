# Context Assigns

Callbacks that are called while the index and show views are rendered receive the assigns of the LiveView, for example `c:Backpex.LiveResource.can?/3`, `c:Backpex.LiveResource.index_row_class/4`, `c:Backpex.LiveResource.filters/1`, the callbacks of item actions and filters, and the functions and callbacks of fields.

By default, Backpex passes all assigns. LiveView cannot know which of them these callbacks actually use, so it re-renders the table with every field component, the filters, the action buttons and the fields of the show view whenever any assign of the LiveView changes, even one that is only used somewhere else, like the visibility of the metrics or an assign of your own `render_resource_slot/3`.

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

These parts are then only re-rendered when their data or one of these assigns changes.

> #### Warning {: .warning}
>
> These callbacks no longer see any other assign. Add every assign that your `can?/3`, `index_row_class/4`, `filters/1`, item actions, filters and fields read to `context_assigns`. The `:socket` only carries the router and endpoint, so use `:all` if your callbacks need anything else from it.

Functions that do not run while rendering, like the `item_query` of the adapter config or the queries of filters, still receive all assigns.
