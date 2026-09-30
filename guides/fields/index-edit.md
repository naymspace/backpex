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

Render the form with `Backpex.HTML.Form.index_form/1`, assign it with `Backpex.Field.assign_index_form/1` and implement [index_editable_change/3](Backpex.Field.html#c:index_editable_change/3). The index view only saves the edits of fields that implement this callback. It saves the value with all of its assigns, like the edit form, so the changeset, `c:Backpex.LiveResource.can?/3` and `c:Backpex.LiveResource.on_item_updated/2` receive the same assigns whatever the `:context_assigns` option of the LiveResource is. When the value cannot be saved, `assign_index_form/1` keeps it in the form and assigns `@valid` as `false`.

```elixir
@impl Backpex.Field
def render_index_form(assigns) do
  assigns = Backpex.Field.assign_index_form(assigns)

  ~H"""
  <div>
    <Backpex.HTML.Form.index_form form={@form} name={@name} item={@item} live_resource={@live_resource}>
      <Backpex.HTML.Form.input
        type="text"
        field={@form[:value]}
        input_class={["input input-sm", !@valid && "input-error"]}
        phx-debounce="100"
        readonly={@readonly}
        hide_errors
        aria-label={@field_options[:label]}
      />
    </Backpex.HTML.Form.index_form>
  </div>
  """
end
```

`index_editable_change/3` returns the change to save. Most fields save the value to the field of the same name:

```elixir
@impl Backpex.Field
def index_editable_change({name, _field_options}, value, _assigns), do: %{name => value}
```

`Backpex.Fields.BelongsTo` saves the foreign key instead, and only of an option of its select. Return `:error` to refuse a value, which the index view then marks as invalid. A field could also trim the value before saving it:

```elixir
@impl Backpex.Field
def index_editable_change({name, _field_options}, value, _assigns), do: %{name => String.trim(value)}
```

Index forms that send their own event to the field component with `phx-target={@myself}` and save it with `Backpex.Field.handle_index_editable/3` keep working. They save with the assigns of the field component, which only include the listed assigns when `:context_assigns` is a list.

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
