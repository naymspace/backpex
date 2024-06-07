# Defaults

You can assign default values to fields in your resource configuration file. This is useful when you want to provide a default value for a field that is not required.

## Configuration

To define a default value for a field, you need to set the `default` option in the field configuration. The `default` option has to return a function that receives the assigns and returns the default value.

```elixir
# in your resource configuration file
@impl Backpex.LiveResource
def fields do
[
    username: %{
        default: fn _assigns -> "Default Username" end
    }
]
end
```

The example above will assign the default value `"Default Username"` to the `username` field.
