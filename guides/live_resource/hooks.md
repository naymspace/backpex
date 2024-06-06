# Hooks

You may define hooks that are called before their respective action. Those hooks are `on_item_created`, `on_item_updated` and `on_item_deleted`.

> #### Info {: .info}
>
> Note that the hooks are called after the changes have been persisted to the database.

## Configuration

To add a hook to a resource, you need to implement the [on_item_created/2](Backpex.LiveResource.html#c:on_item_created/2), [on_item_updated/2](Backpex.LiveResource.html#c:on_item_updated/2) or [on_item_deleted/2](Backpex.LiveResource.html#c:on_item_deleted/2) callback in your resource configuration file.

```elixir
# in your resource configuration file

@impl Backpex.LiveResource
def on_item_created(socket, item) do
    # do something
    socket
end
```

The example above will call the `on_item_created` hook after an item has been created.
