# Error Customization

You can customize the error messages for each field in your resource configuration file.

## Configuration

To customize the error messages for a field, you need to define a `translate_error/1` function in the field configuration. The function receives the error tuple and must return a tuple with the message and metadata.

```elixir
@impl Backpex.LiveResource
def fields do
[
    number: %{
        module: Backpex.Fields.Number,
        label: "Number",
        translate_error: fn
            {_msg, [type: :integer, validation: :cast] = metadata} = _error ->
                {"has to be a number", metadata}

            error ->
                error
        end
    }
]
end
```

The example above will return the message `"has to be a number"` when the input is not a number.
