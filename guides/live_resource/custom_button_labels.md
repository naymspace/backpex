# Custom button labels

You can customize the label of the buttons that are displayed in the Live Resource. This is useful if you want to display a different label than the default one.

We currently support customizing the label of the create button.

## Configuration for the create button label

```elixir
# in your resource configuration file

@impl Backpex.LiveResource
def create_button_label, do: "Create a new user"
```

The create button will now display the label "Create a new user" instead of the default "Create %{resource}".