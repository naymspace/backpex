# Context Assigns

Callbacks that are called while the index and show views are rendered receive the assigns of the LiveView, for example `c:Backpex.LiveResource.can?/3`, `c:Backpex.LiveResource.index_row_class/4`, the callbacks of item actions, the `render/1` and `render_form/1` callbacks of filters, and the functions and callbacks of fields.

By default, Backpex passes all assigns. LiveView cannot know which of them these callbacks actually use, so it re-renders the table with every field component, the filters, the action buttons and the fields of the show view whenever any assign of the LiveView changes, even one that is only used somewhere else, like the visibility of the metrics or an assign of your own `render_resource_slot/3`.

## Configure LiveResource

Set the `context_assigns` option to the assigns your callbacks need in addition to the ones Backpex always passes (`:live_resource`, `:live_action`, `:params`, `:fields`, `:item_actions`, `:return_to`, the `:item` of the show view, which is `nil` on the index view or the `base_schema` of a resource action while one is open, and a `:socket` for building routes):

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
> These callbacks no longer see any other assign. Add every assign that your `can?/3`, `index_row_class/4`, item actions, filters and fields read to `context_assigns`. The `:socket` only carries the router and endpoint, so use `:all` if your callbacks need anything else from it.

`c:Backpex.LiveResource.filters/1` and the `can?/1` callback of filters always receive all assigns. The index view evaluates them on every render. Functions that do not run while rendering also receive all assigns, for example the `item_query` of the adapter config, the queries of filters and saving an inline edit of an `index_editable` field. The changeset and `c:Backpex.LiveResource.can?/3` of an inline edit receive the same assigns as in the edit form, and `c:Backpex.LiveResource.on_item_updated/2` receives the socket of the LiveView. Custom fields that save their inline edits with `Backpex.Field.handle_index_editable/3` instead of rendering `Backpex.HTML.Form.index_form/1` only receive the listed assigns, see the [Index Edit](../fields/index-edit.md#custom-index-editable-implementation) guide.
