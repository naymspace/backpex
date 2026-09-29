# Index Edit

A small number of fields support index editable. These fields can be edited inline on the index view.

## Configuration

To enable index editable for a field, you need to set the `index_editable` option to `true` in the field configuration.

```elixir
# in your resource configuration file
def fields do
[
    name: %{
        module: Backpex.Fields.Text,
        label: "Name",
        index_editable: true
    }
]
end
```

The example above will enable index editable for the `name` text field.

## Supported fields

- `Backpex.Fields.BelongsTo`
- `Backpex.Fields.Date`
- `Backpex.Fields.DateTime`
- `Backpex.Fields.Email`
- `Backpex.Fields.Number`
- `Backpex.Fields.Select`
- `Backpex.Fields.Text`

## Custom index editable implementation

You can add index editable support to your custom fields by defining the [render_index_form/1](Backpex.Field.html#c:render_index_form/1) function and enabling index editable for your field.

## Loading data for all rows at once

Backpex renders the index form of every row as its own live component. If `render_index_form/1` loads data, for
example the options of a select, it runs one query per row on every render of the index view.

Implement the [index_assigns/3](Backpex.Field.html#c:index_assigns/3) callback to load that data once for all rows
instead. Backpex calls it whenever the items of the index view change, e.g. when loading a page, filtering or on item
events, and merges the returned map into the assigns of the field in every row. It receives the field, the items of the
page and the assigns of the index view. Return data that differs per row keyed by the item.

```elixir
@impl Backpex.Field
def index_assigns(_field, items, _assigns) do
  category_ids = Enum.map(items, & &1.category_id)
  tags_by_category_id = MyApp.Tags.list_tags_by_category_ids(category_ids)

  tag_options =
    Map.new(items, fn item ->
      tags = Map.get(tags_by_category_id, item.category_id, [])
      {item.id, Enum.map(tags, &{&1.name, &1.id})}
    end)

  %{tag_options: tag_options}
end

@impl Backpex.Field
def render_index_form(assigns) do
  assigns = assign(assigns, :options, Map.get(assigns.tag_options, assigns.item.id, []))

  # render the select with @options
end
```

As the data only reflects saved items, options that depend on another field of the row are updated once that field
has been saved and Backpex received the item event.

`Backpex.Fields.BelongsTo` uses this callback to load its options once for all rows.
