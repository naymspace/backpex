# Readonly

Fields can be configured to be readonly. In edit view, these fields are rendered with the additional HTML attributes `readonly` and `disabled`, ensuring that the user cannot interact with the field or change its value.

In index view, if readonly and index editable is set to `true`, forms will be rendered with the `readonly` HTML attribute.

## Supported fields

On index view, read-only is supported for all fields with the index editable option (see [Index Edit](index-edit.md)).

On edit view, read-only is supported for:
- `Backpex.Fields.Date`
- `Backpex.Fields.DateTime`
- `Backpex.Fields.Number`
- `Backpex.Fields.Text`
- `Backpex.Fields.Textarea`

## Configuration

To enable read-only for a field, you need to set the `readonly` option to `true` in the field configuration. This key must contain either a boolean value or a function that returns a boolean value.

```elixir
# in your resource configuration file
def fields do
[
    rating: %{
        module: Backpex.Fields.Text,
        label: "Rating",
        readonly: fn assigns ->
            assigns.current_user.role in [:employee]
        end
    }
]
end
```

```elixir
# in your resource configuration file
def fields do
[
    rating: %{
        module: Backpex.Fields.Text,
        label: "Rating",
        readonly: true
    }
]
end
```

## Readonly for custom fields

You can also add readonly functionality to a custom field. To do this, you need to define a [`render_form_readonly/1`](Backpex.Field.html#c:render_form_readonly/1) function. This function must return markup to be used when readonly is enabled.

```elixir
@impl Backpex.Field
def render_form_readonly(assigns) do
~H"""
<div>
    <Layout.field_container>
        <:label>
            <Layout.input_label text={@field[:label]} />
        </:label>
        <BackpexForm.field_input
            type="text"
            form={@form}
            field_name={@name}
            field_options={@field_options}
            readonly
            disabled
        />
    </Layout.field_container>
</div>
"""
end
```

When defining a custom field with index editable support, you need to handle the readonly state in the index editable markup. There is a `readonly` value in the assigns, which will be `true` or `false`.
