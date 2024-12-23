# Custom Fields

Backpex ships with a set of default fields that can be used to create content types. See [Built-in Field Types](what-is-a-field.md#built-in-field-types) for a complete list of the default fields. In addition to the default fields, you can create custom fields for more advanced use cases.

When creating your own custom field, you can use the `field` macro from the `BackpexWeb` module. It automatically implements the `Backpex.Field` behavior and defines some aliases and imports.

Note that a field has to be a [LiveComponent](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveComponent.html).

> #### Warning {: .warning}
>
> As Backpex is still under active development in a 0.X version, it can be assumed that there will be breaking changes to the
> fields API in future releases, which will require you to update your custom fields.

## Creating a Custom Field

The simplest version of a custom field would look like this:

```elixir
use BackpexWeb, :field

@impl Backpex.Field
def render_value(assigns) do
~H"""
<p>
    <%= HTML.pretty_value(@value) %>
</p>
"""
end

@impl Backpex.Field
def render_form(assigns) do
~H"""
<div>
    <Layout.field_container>
    <:label>
        <Layout.input_label text={@field_options[:label]} />
    </:label>
    <BackpexForm.input
        type="text"
        field={@form[@name]}
        translate_error_fun={Backpex.Field.translate_error_fun(@field_options, assigns)}
        phx-debounce={Backpex.Field.debounce(@field_options, assigns)}
        phx-throttle={Backpex.Field.throttle(@field_options, assigns)}
    />
    </Layout.field_container>
</div>
"""
end
```

The `render_value/1` function returns markup that is used to display a value on `index` and `show` views.
The `render_form/1` function returns markup that is used to render a form on `edit` and `new` views.

See `Backpex.Field` for more information on the available callback functions. For example, you can implement `render_index_form/1` to make the field editable in the index view.

## Add field option validation

With Backpex v0.9 we are validating field options. This ensures that only field options that are actually used by the field can be defined in the field options map. So if your custom field requires certain field options, make sure you define them.

Note that we use [NimbleOptions](https://hexdocs.pm/nimble_options) to validate field options.

To add field option validation pass a config schema to `use Backpex.Field`.

```elixir
@config_schema [
    custom_option: [
        doc: "A custom field option.",
        type: :string
    ],
    # see https://hexdocs.pm/nimble_options/NimbleOptions.html
    # or any other core backpex field for examples...
]

use Backpex.Field, config_schema: @config_schema
```

You can then access your custom option safely in your field.

```elixir
@impl Backpex.Field
def render_value(assigns) do
    custom_option = assigns.field_options[:custom_option]

    # ...
end
```
