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
