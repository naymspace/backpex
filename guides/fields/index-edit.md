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
