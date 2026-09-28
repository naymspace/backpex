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
example the options of a select, it runs one query per row.

Implement the [assign_index_forms/1](Backpex.Field.html#c:assign_index_forms/1) callback to load that data for all rows
at once instead. It receives the sockets of all rows whose index form is updated together and has to return them in the
same order. Backpex calls it after `update/2`, so the sockets already contain the assigns of the field, such as the
`item` of the row.

```elixir
@impl Backpex.Field
def assign_index_forms(sockets) do
  category_ids = Enum.map(sockets, & &1.assigns.item.category_id)
  tags_by_category_id = MyApp.Tags.list_tags_by_category_ids(category_ids)

  Enum.map(sockets, fn socket ->
    tags = Map.get(tags_by_category_id, socket.assigns.item.category_id, [])
    assign(socket, :tag_options, Enum.map(tags, &{&1.name, &1.id}))
  end)
end

@impl Backpex.Field
def render_index_form(assigns) do
  # use @tag_options instead of loading the options here
end
```

`Backpex.Fields.BelongsTo` uses this callback to load its options once for all rows.
