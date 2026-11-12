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
use Backpex.Field

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
        <Layout.input_label for={@form[@name]} text={@field_options[:label]} />
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

## Form params

The form passes only the params of the fields an admin may edit to the changeset and drops all others. A field submits
the param of its name by default, e.g. `change[my_field]`. If `render_form/1` renders inputs under other names, return
all of them from `c:Backpex.Field.param_keys/2`:

```elixir
@impl Backpex.Field
def param_keys({name, _field_options}, _assigns) do
  name = Atom.to_string(name)

  [name, name <> "_confirmation"]
end
```

If the form of the field submits rows of nested params, e.g. through `inputs_for`, return `{key, keys}` for them. The
form then keeps only the given keys in each row, as `Backpex.Fields.InlineCRUD` does for the child fields an admin may
edit. The param may be a list of rows, a map of indexes to rows, or the one row of a single nested object
(`embeds_one`, `has_one`).

```elixir
@impl Backpex.Field
def param_keys({name, _field_options}, _assigns) do
  name = Atom.to_string(name)

  [{name, ["id", "_persistent_id", "street", "city"]}, name <> "_order", name <> "_delete"]
end
```

`inputs_for` submits the primary key and `_persistent_id` with each row, so return both. The example also returns the
params of the `:sort_param` and `:drop_param` of `Ecto.Changeset.cast_assoc/3` and `Ecto.Changeset.cast_embed/3`,
here `<name>_order` and `<name>_delete`: leave them out if the form doesn't submit them.

A field with an `upload_key` keeps the hidden input of the upload UI without returning it.

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

The schema is compiled together with the field module, so an invalid schema fails the compilation of the field.

You can then access your custom option safely in your field.

```elixir
@impl Backpex.Field
def render_value(assigns) do
    custom_option = assigns.field_options[:custom_option]

    # ...
end
```

## Custom upload fields

An upload field is a field whose module implements the upload callbacks, or a field with an `:upload_key` option.
Besides `c:Backpex.Field.assign_uploads/2`, it implements four callbacks that the form component calls on the field's
module:

- `c:Backpex.Field.list_existing_files/2` returns the files the item has.
- `c:Backpex.Field.put_upload_change/7` puts the files into the params of the changeset.
- `c:Backpex.Field.consume_upload/5` consumes each uploaded entry after the item has been saved.
- `c:Backpex.Field.remove_uploads/4` removes the files the user removed during an edit.

`Backpex.Fields.Upload` implements them by calling the functions you pass as options. A custom upload field gets the
field (`{name, field_options}`) as the first argument, so it can implement them once for every field it's used for and
work out what it needs from the field, such as the column to read the files from.

To reuse the upload UI, delegate rendering and `assign_uploads/2` to `Backpex.Fields.Upload`. Its `render_form/1` and
`render_value/1` list the existing files through your `list_existing_files/2`. Its `render_form/1` shows the upload
errors with the texts of your `c:Backpex.Field.upload_error/4`, if your module implements it, and with its own texts
otherwise.

The upload is named after the field, unless the field has an `:upload_key` option (see `Backpex.Field.upload_key/1`).

A custom upload field that doesn't implement the callbacks keeps working, as long as it has an `:upload_key` option:
the form component then calls them on `Backpex.Fields.Upload`, which reads the `:list_existing_files`,
`:put_upload_change`, `:consume_upload` and `:remove_uploads` functions from the field options. See
`Backpex.Field.upload_module/1`.
