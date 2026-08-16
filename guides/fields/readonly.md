# Readonly

Fields can be configured to be readonly. In edit view, readonly fields prevent users from interacting with the field or changing its value, while still displaying the current value.

In index view, if readonly and index editable are both set to true, forms will be rendered with the `readonly` HTML attribute.

## Supported fields

On index view, readonly is supported for all fields with the index editable option (see [Index Edit](index-edit.md)).

On edit view, `readonly` is a global field option defined on `Backpex.Field`, so every built-in field type inherits it. It accepts either a `boolean` or a function `(assigns -> boolean)`.

Built-in fields render readonly using one of three strategies:

**Native `readonly` (text-like inputs)**

These fields render the browser's native `readonly` attribute on their input, so the value is still focusable and selectable but cannot be changed:

- `Backpex.Fields.Text`
- `Backpex.Fields.Textarea`
- `Backpex.Fields.Number`
- `Backpex.Fields.Date`
- `Backpex.Fields.DateTime`
- `Backpex.Fields.Time`
- `Backpex.Fields.Email`
- `Backpex.Fields.URL`
- `Backpex.Fields.Currency`

**`disabled` (control-style inputs)**

Native `readonly` does not apply to these control types, so they render as `disabled` instead:

- `Backpex.Fields.Select`
- `Backpex.Fields.MultiSelect`
- `Backpex.Fields.Boolean` — renders as a disabled toggle
- `Backpex.Fields.BelongsTo`
- `Backpex.Fields.HasMany` — dropdown is rendered as an inert element; selected badges lose the remove control

**Custom readonly rendering**

A few fields need tailored behavior beyond a single attribute:

- `Backpex.Fields.Upload` — the drop target and "Upload a file" link are disabled, the cancel/remove buttons on pending and existing entries are hidden, and the existing-file list is still displayed so users can see what is attached.
- `Backpex.Fields.InlineCRUD` — nested row fields become readonly, and the per-row delete checkbox and the add-row control are hidden entirely.
- `Backpex.Fields.HasManyThrough` — the Actions column (edit/remove buttons) is hidden, the "new relational" button is disabled, and pivot and select inputs inside the modal are rendered as disabled.

## Configuration

To enable readonly for a field, you need to set the `readonly` option in the field configuration. This key must contain either a boolean value or a function that returns a boolean value.

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

You can also add readonly functionality to a custom field. To do this, you need to handle the readonly state in the `c:Backpex.Field.render_form/1` function of your custom field. You can access the readonly value from the assigns, which will be `true` or `false`.

```elixir
@impl Backpex.Field
def render_form(assigns) do
~H"""
<div>
  <Layout.field_container>
    <:label>
        <Layout.input_label for={@form[@name]} text={@field[:label]} />
    </:label>
    <BackpexForm.input
      type="text"
      field={@form[@name]}
      translate_error_fun={Backpex.Field.translate_error_fun(@field_options, assigns)}
      phx-debounce={Backpex.Field.debounce(@field_options, assigns)}
      phx-throttle={Backpex.Field.throttle(@field_options, assigns)}
      readonly={@readonly}
    />
  </Layout.field_container>
</div>
"""
end
```

If your readonly logic is more complex, you can also use a dedicated function that returns the markup for the readonly state.

```elixir
@impl Backpex.Field
def render_form(%{readonly: true} = assigns) do
# Return readonly markup
end

def render_form(%{readonly: false} = assigns) do
# Return editable markup
end
```

When defining a custom field with index editable support, you need to handle the readonly state in `c:Backpex.Field.render_index_form/1`. There is also a readonly value in the assigns, which will be `true` or `false`.
