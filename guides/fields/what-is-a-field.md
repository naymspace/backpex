# What is a Field?

Backpex fields are the building blocks of a resource. They define the data that will be displayed and manipulated in the resource views. Fields can be of different types, such as text, number, date, and select. Each field type has its own configuration options and behavior. Typically, you want to configure a field for each type of data you want to display in your resource.

Backpex ships with a set of built-in field types, but you can also create custom fields to fit your specific needs.

## Built-in Field Types

Backpex provides the following built-in field types:

- `Backpex.Fields.BelongsTo`
- `Backpex.Fields.Boolean`
- `Backpex.Fields.Currency`
- `Backpex.Fields.DateTime`
- `Backpex.Fields.Date`
- `Backpex.Fields.Email`
- `Backpex.Fields.HasManyThrough`
- `Backpex.Fields.HasMany`
- `Backpex.Fields.InlineCRUD`
- `Backpex.Fields.MultiSelect`
- `Backpex.Fields.Number`
- `Backpex.Fields.Select`
- `Backpex.Fields.Text`
- `Backpex.Fields.Textarea`
- `Backpex.Fields.Upload`
- `Backpex.Fields.URL`

You can click on each field type to see its documentation and configuration options.

## Configuration

To define fields for a resource, you need to implement the [`fields/0`](Backpex.LiveResource.html#c:fields/0) callback in your resource module. This function must return a list of field configurations.

```elixir
@impl Backpex.LiveResource
def fields do
  [
    username: %{
      module: Backpex.Fields.Text,
      label: "Username"
    },
    age: %{
      module: Backpex.Fields.Number,
      label: "Age"
    }
  ]
end
```

The example above will define two fields: `username` and `age`. Both fields use the built-in field types `Backpex.Fields.Text` and `Backpex.Fields.Number`, respectively.

## Field Configuration

Each field configuration must contain the following keys:

- `module`: The module that implements the field behavior.
- `label`: The label that will be displayed for the field.

In addition to these keys, you can configure each field with additional options specific to the field type. For example, a text field can have a `placeholder` option to set a placeholder text for the input field.

```elixir
@impl Backpex.LiveResource
def fields do
  [
    username: %{
      module: Backpex.Fields.Text,
      label: "Username",
      placeholder: "Enter your username"
    }
  ]
end
```

The example above will set the placeholder `"Enter your username"` for the `username` field.

The following sections will cover general field options and how to create custom fields.
