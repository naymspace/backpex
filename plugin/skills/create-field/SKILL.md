---
name: create-field
description: Use when creating custom Backpex field types, implementing the Backpex.Field behaviour, or adding fields to a LiveResource's fields/0 callback.
---

# Creating Backpex Fields

You are an expert at creating fields for Backpex, a Phoenix LiveView admin panel library. When the user wants to add or create a field, follow this process:

1. **Determine if a built-in field works** from the list below
2. **If custom**, generate a module implementing `Backpex.Field`
3. **Wire it into the LiveResource** by updating the `fields/0` callback

## Built-in Field Modules

| Module | Use for |
|--------|---------|
| `Backpex.Fields.Text` | Single-line text inputs |
| `Backpex.Fields.Textarea` | Multi-line text inputs |
| `Backpex.Fields.Number` | Numeric values |
| `Backpex.Fields.Boolean` | Checkboxes / toggles |
| `Backpex.Fields.Select` | Dropdown with static options |
| `Backpex.Fields.MultiSelect` | Multi-value dropdown |
| `Backpex.Fields.Date` | Date picker |
| `Backpex.Fields.DateTime` | Date and time picker |
| `Backpex.Fields.Time` | Time picker |
| `Backpex.Fields.Currency` | Formatted currency values |
| `Backpex.Fields.URL` | URLs with link rendering |
| `Backpex.Fields.Email` | Email addresses |
| `Backpex.Fields.BelongsTo` | belongs_to associations |
| `Backpex.Fields.HasMany` | has_many associations |
| `Backpex.Fields.HasManyThrough` | has_many through associations |
| `Backpex.Fields.InlineCRUD` | Inline editing of embeds_many / has_many |
| `Backpex.Fields.Upload` | File uploads |

## Common Field Options (available on all fields)

| Option | Type | Description |
|--------|------|-------------|
| `module` | atom | **Required.** The field module |
| `label` | string | **Required.** Display label |
| `searchable` | boolean | Enable search on this column |
| `orderable` | boolean | Enable column sorting |
| `visible` | `fn assigns -> bool` | Controls visibility on all views except index |
| `can?` | `fn assigns -> bool` | Controls visibility on all views including index |
| `only` | list | Restrict to specific views: `:new`, `:edit`, `:show`, `:index` |
| `except` | list | Hide from specific views |
| `panel` | atom | Group into a named panel |
| `index_editable` | boolean or `fn assigns -> bool` | Enable inline editing on index |
| `align` | `:left`, `:center`, `:right` | Column alignment on index |
| `align_label` | `:top`, `:center`, `:bottom`, or `fn assigns -> atom` | Label alignment in forms |
| `index_column_class` | string or `fn assigns -> string` | Extra CSS class on index column |
| `render` | `fn assigns -> HEEx` | Override value rendering |
| `render_form` | `fn assigns -> HEEx` | Override form rendering |
| `help_text` | string or `fn assigns -> string` | Text below form input |
| `default` | `fn assigns -> value` | Default value for new items |
| `select` | `dynamic(...)` | Ecto dynamic expression for computed/virtual fields |
| `custom_alias` | atom | Custom alias for the field in queries |
| `translate_error` | `fn {msg, meta} -> {msg, meta}` | Custom error message formatting |

## Creating a Custom Field

Implement `Backpex.Field` with a `@config_schema` for field-specific options.

### Required Callbacks

```elixir
@callback render_value(assigns :: map()) :: %Phoenix.LiveView.Rendered{}
@callback render_form(assigns :: map()) :: %Phoenix.LiveView.Rendered{}
```

`render_value/1` is used on both index and show views. `render_form/1` is used on new and edit views.

### Callbacks With Defaults (overridable)

These are provided by `use Backpex.Field` and can be overridden as needed:

```elixir
@callback render_index_form(assigns)  # For index_editable support (only truly optional callback)
@callback display_field(field)         # Default: returns field name
@callback schema(field, schema)        # Default: returns the schema
@callback association?(field)          # Default: false
@callback assign_uploads(field, socket) # Default: returns socket unchanged
@callback before_changeset(changeset, attrs, metadata, repo, field, assigns) # 6-arity
@callback search_condition(schema_name :: binary(), field_name :: binary(), search_string :: binary()) # Default: ilike
```

### Key Assigns Available in Templates

| Assign | Description |
|--------|-------------|
| `@value` | Current field value |
| `@name` | Field key atom |
| `@field_options` | Merged field options map |
| `@form` | Phoenix.HTML.Form (in form renders) |
| `@item` | The full resource item struct |
| `@live_action` | `:index`, `:edit`, `:new`, or `:show` |
| `@readonly` | Boolean from readonly option |
| `@myself` | LiveComponent reference for phx-target |

### Example Custom Field

```elixir
defmodule MyAppWeb.Fields.ColorPicker do
  @config_schema [
    palette: [
      doc: "List of allowed hex colors.",
      type: {:list, :string}
    ]
  ]

  use Backpex.Field, config_schema: @config_schema

  @impl Backpex.Field
  def render_value(assigns) do
    ~H"""
    <div class="flex items-center gap-2">
      <span class="inline-block h-4 w-4 rounded-full" style={"background-color: #{@value}"}></span>
      <span>{@value}</span>
    </div>
    """
  end

  @impl Backpex.Field
  def render_form(assigns) do
    ~H"""
    <div>
      <Layout.field_container>
        <:label align={Backpex.Field.align_label(@field_options, assigns, :center)}>
          <Layout.input_label for={@form[@name]} text={@field_options[:label]} />
        </:label>
        <BackpexForm.input
          type="color"
          field={@form[@name]}
          translate_error_fun={Backpex.Field.translate_error_fun(@field_options, assigns)}
          help_text={Backpex.Field.help_text(@field_options, assigns)}
          phx-debounce={Backpex.Field.debounce(@field_options, assigns)}
        />
      </Layout.field_container>
    </div>
    """
  end
end
```

### Using it in a LiveResource

```elixir
@impl Backpex.LiveResource
def fields do
  [
    color: %{
      module: MyAppWeb.Fields.ColorPicker,
      label: "Color",
      palette: ["#ff0000", "#00ff00", "#0000ff"]
    }
  ]
end
```

## Declaring Fields in a LiveResource

`fields/0` returns a keyword list. Each key is the Ecto schema field atom, each value is a map of options.

```elixir
@impl Backpex.LiveResource
def fields do
  [
    title: %{
      module: Backpex.Fields.Text,
      label: "Title",
      searchable: true
    },
    body: %{
      module: Backpex.Fields.Textarea,
      label: "Body",
      except: [:index]
    },
    category: %{
      module: Backpex.Fields.BelongsTo,
      label: "Category",
      display_field: :name,
      searchable: true,
      live_resource: MyAppWeb.CategoryLive
    },
    inserted_at: %{
      module: Backpex.Fields.DateTime,
      label: "Created At",
      only: [:index, :show]
    }
  ]
end
```

## Conventions

- **File location**: `lib/my_app_web/fields/<snake_case_name>.ex`
- **Module naming**: `MyAppWeb.Fields.<FieldName>`
- **Always declare `@config_schema`** before `use Backpex.Field` for custom field-specific options
- **Use `Layout.field_container`** and `Layout.input_label`  in `render_form/1` for consistent form layout
- **Use `BackpexForm.input`** for standard input rendering with error handling
