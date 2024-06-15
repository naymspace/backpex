# Additional classes for index table rows

You can add additional classes to table rows on the index view. This allows you, for example, to color the rows. 

## Configuration

To add additional classes to table rows on the index view, you need to implement the [index_row_class/4](Backpex.LiveResource.html#c:index_row_class/4) callback in your resource configuration file.

```elixir
# in your resource configuration file

@impl Backpex.LiveResource
def index_row_class(assigns, item, selected, index), do: "bg-yellow-100"
```

The example above will add the `bg-yellow-100` class to all table rows on the index view.

> #### Info {: .warning}
>
> Note that we call the function twice. Once for the row on the `tr` element and a second time for the item action overlay, because in most cases the overlay should have the same style applied.
