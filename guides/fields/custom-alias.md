# Custom Alias

Backpex automatically generates aliases for queries in your fields. However, if you try to add two `Backpex.Field.BelongsTo` fields of the same association, you will encounter an error indicating that the alias is already in use by another field. To resolve this issue, Backpex allows the assignment of custom aliases to fields, eliminating naming conflicts in queries.

## Configuration

To use a custom alias, define the `custom_alias` key in your field configuration. The value of the `custom_alias` key must be a unique atom that is not already in use by another field.


```elixir
@impl Backpex.LiveResource
def fields do
[
    second_category: %{
        module: Backpex.Fields.BelongsTo,
        label: "Second Category",
        display_field: :name,
        searchable: true,
        custom_alias: :second_category,
        select: dynamic([second_category: sc], sc.name)
    },
]
end
```

The example above will assign the alias `:second_category` to the `second_category` field. This alias can now be used in queries without causing conflicts with other fields.