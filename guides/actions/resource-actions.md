# Resource Actions

Resource actions are a way to define custom actions that can be performed on a whole resource.

A resource action could be something like exporting a resource to a CSV file, or sending an email to all users in a resource.

## Configuration

You define resource actions by implementing the [`resource_actions/0`](Backpex.LiveResource.html#c:resource_actions/0) callback in your resource configuration module.

Let's say you have a resource called `User` and you want to add a resource action to invite users to your application.

First, you need to add the resource action to your resource configuration module.

```elixir
# in your resource configuration file

@impl Backpex.LiveResource
def resource_actions() do
[
    invite: %{
        module: MyWebApp.Admin.ResourceActions.Invite,
    }
]
end
```

Each resource action is a map with at least the module key. The module key should point to the module that implements the resource action. The key in the keyword list is the unique `id` of the resource action.

## Implementing a Resource Action

A resource action is a module that uses the `Backpex.ResourceAction` module.

```elixir
defmodule MyAppWeb.Admin.Actions.Invite do
    use Backpex.ResourceAction

    import Ecto.Changeset

    @impl Backpex.ResourceAction
    def label, do: "Invite"

    @impl Backpex.ResourceAction
    def title, do: "Invite user"

    # you can reuse Backpex fields in the field definition
    @impl Backpex.ResourceAction
    def fields do
        [
            email: %{
                module: Backpex.Fields.Text,
                label: "Email",
                type: :string
            }
        ]
    end

    @impl Backpex.ResourceAction
    def changeset(change, attrs) do
        change
        |> cast(attrs, [:email])
        |> validate_required([:email])
        |> validate_email(:email)
    end

    @impl Backpex.ResourceAction
    def handle(_socket, data) do
        # Send mail

        # We suppose there was no error.
        if true do
            {:ok, "An invitation email to #{data.email} was sent successfully."}
        else
            {:error, "An error occurred while sending an invitation email to  #{data.email}!"}
        end
    end
end
```

See `Backpex.ResourceAction` for a documentation of the callbacks.

The [`handle/2`](Backpex.ResourceAction.html#c:handle/2) callback is called when the user submits the form to perform the action. In this example, we suppose there was no error sending the invitation email and return a success message.

You can access the email entered by the user in the `data` argument. The `data` argument is a map that contains the casted and validated data from the form (received from [`Ecto.Changeset.apply_action/2`](https://hexdocs.pm/ecto/Ecto.Changeset.html#apply_action/2)).

We validate the email address using the `validate_email/2` function provided by the `Ecto.Changeset` module.

> #### Info {: .info}
>
> Each resource action has its own route. The route is defined by the `id` of the resource action. If you use the [`live_resource/3`](Backpex.Router.html#live_resources/3) macro, the route is automatically added to the live resource.