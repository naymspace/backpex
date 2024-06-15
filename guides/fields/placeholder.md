# Placeholder

You can configure a placeholder for form fields. The placeholder will be displayed in the input field when the field is empty.

> #### Important {: .info}
>
> Note that the option only works for input fields that are **not** type `textarea`, `select`, `toggle` or `checkbox`.
> 
## Configuration

To set a placeholder for a field, you need to set the `placeholder` option in the field configuration. The `placeholder` either has to be a string or a function that receives the assigns and returns the placeholder string.

```elixir
# in your resource configuration file
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
