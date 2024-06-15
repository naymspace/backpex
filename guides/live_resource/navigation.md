# Navigation


By default Backpex redirects to the index page after creating or updating an item. You can customize this behavior.

## Configuration

To define a custom navigation path, you need to implement the [return_to/4](Backpex.LiveResource.html#c:return_to/4) callback in your resource configuration file:

```elixir
# in your resource configuration file

@impl Backpex.LiveResource
def return_to(socket, assigns, live_action, item) do
    ~p"/home"
end
```

The example above will redirect to the `/home` path after saving an item.
