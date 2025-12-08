# LiveResource Authorization

You are able to define authorization rules for your resources. The authorization rules are defined in the resource configuration file and are used to control access to certain actions.

## Configuration

To define authorization rules for a resource, you need to implement the [`can?/3`](Backpex.LiveResource.html#c:can?/3) callback in the resource configuration file.

```elixir
# in your resource configuration file
@impl Backpex.LiveResource
def can?(assigns, :show, item), do: false
def can?(assigns, action, item), do: true
```

The example above will deny access to the `show` action and allow access to all other actions.

```elixir
# in your resource configuration file
@impl Backpex.LiveResource
def can?(assigns, :show, item) do
    user = assigns.current_user

    item.user_id == user.id
end

def can?(assigns, action, item), do: true
```

The example above will deny access to the `show` action if the `user_id` of the item does not match the `id` of the current user.

You can also use [`can?/3`](Backpex.LiveResource.html#c:can?/3) to restrict access to item or resource actions.

```elixir
# in your resource configuration file
@impl Backpex.LiveResource
def can?(_assigns, :my_item_action, item), do: item.role == :admin
def can?(assigns, action, item), do: true
```

The example above will deny access to the `my_item_action` action if the `role` of the item is not `:admin`.

## Parameters

The `can?` callback receives the following parameters:

- `assigns` - the assigns of the LiveView
- `action` - the action that is being authorized (available actions are: `:index` , `:new`, `:show`, `:edit`, `:delete`, `:your_item_action_key`, `:your_resource_action_key`)
- `item` - the item that is being authorized

## Return value

The `can?` callback must return a boolean value. If the return value is `true`, the action is allowed. If the return value is `false`, the action is denied.