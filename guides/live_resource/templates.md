# Templates

You can customize certain template parts of Backpex. While you can only use our app shell layout, you can also define functions to provide additional templates to be rendered on the resource LiveView or completely overwrite certain parts like the header or main content.

See [render_resource_slot/3](Backpex.LiveResource.html#c:render_resource_slot/3) for supported positions.

## Configuration

To add a custom template to a resource, you need to implement the [render_resource_slot/3](Backpex.LiveResource.html#c:render_resource_slot/3) callback in your resource configuration file.

```elixir
# in your resource configuration file
@impl Backpex.LiveResource
def render_resource_slot(assigns, :index, :before_main), do: ~H"Hello World!"
```

The example above will render the string "Hello World!" before the main content of the index view.
