# Debounce and Throttle

You can debounce and throttle the input of a field in the edit view. This is useful when you want to reduce the number of requests sent to the server.

## Configuration

To enable debounce or throttle for a field, you need to set the `debounce` or `throttle` option in the field configuration.

- `debounce`: Has to return either an integer timeout value (in milliseconds), or "blur". When an integer is provided, emitting the event is delayed by the specified milliseconds. When "blur" is provided, emitting the event is delayed until the field is blurred by the user.
- `throttle`: Has to return an integer timeout value (in milliseconds). The event is emitted at most once every specified milliseconds.

See Phoenix LiveView documentation for more information on [debouncing and throttling](https://hexdocs.pm/phoenix_live_view/bindings.html#rate-limiting-events-with-debounce-and-throttle).

The options can be set to a function that receives the assigns and returns the debounce or throttle value or a static value.

```elixir
# in your resource configuration file
@impl Backpex.LiveResource
def fields do
[
    username: %{
        module: Backpex.Fields.Text,
        label: "Username",
        debounce: 500
    }
]
end
```

The example above will debounce the input of the `username` field by 500 milliseconds.

```elixir
# in your resource configuration file
@impl Backpex.LiveResource
def fields do
[
    username: %{
        module: Backpex.Fields.Text,
        label: "Username",
        debounce: fn _assigns -> 500 end
    }
]
end
```

The example above will debounce the input of the `username` field by 500 milliseconds.

```elixir
# in your resource configuration file
@impl Backpex.LiveResource
def fields do
[
    username: %{
        module: Backpex.Fields.Text,
        label: "Username",
        debounce: "blur"
    }
]
end
```

The example above will debounce the input of the `username` field until the field is blurred by the user.

```elixir
# in your resource configuration file
@impl Backpex.LiveResource
def fields do
[
    username: %{
        module: Backpex.Fields.Text,
        label: "Username",
        throttle: 500
    }
]
end
```

The example above will throttle the input of the `username` field by 500 milliseconds.

```elixir
# in your resource configuration file
@impl Backpex.LiveResource
def fields do
[
    username: %{
        module: Backpex.Fields.Text,
        label: "Username",
        throttle: fn _assigns -> 500 end
    }
]
end
```

The example above will throttle the input of the `username` field by 500 milliseconds.