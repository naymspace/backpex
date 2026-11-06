# Field Authorization

You can define authorization rules for your fields.

## Configuration

To define authorization rules for a field, you may use the `can?/1` callback for a field configuration. It takes the assigns and has to return a boolean value.

```elixir
# in your resource configuration file
@impl Backpex.LiveResource
def fields do
[
    inserted_at: %{
        module: Backpex.Fields.DateTime,
        label: "Created At",
        can?: fn
            %{live_action: :show} = _assigns ->
            true

            _assigns ->
            false
        end
    }
]
end
```

The above example will show the `inserted_at` field only in the show view.

## Saving

The form passes only the params of the fields an admin may edit to the changeset: the fields of the current view that
`can?` allows and that are not readonly. Backpex drops the params of every other field, also of the fields that `only`
and `except` leave out of the view, so a crafted client can't change a value through a field the admin doesn't see.
A field that submits params under other names than its own returns them from `c:Backpex.Field.param_keys/2`.
