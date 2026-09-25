# Navigation

By default, Backpex redirects to the previous resource path (index or show view) after creating or updating an item, 
but you can customize this behavior.

## Configuration

To define a custom navigation path, you need to implement the [return_to/5](Backpex.LiveResource.html#c:return_to/5) callback in your resource configuration file:

```elixir
# in your resource configuration file
@impl Backpex.LiveResource
def return_to(socket, assigns, live_action, _form_action, item) do
    ~p"/home"
end
```

The example above will always redirect to the `/home` path after editing an item.

## Available Live Actions

Backpex supports the following live actions:

- `:index` - The list view of your resource
- `:new` - The form for creating a new resource
- `:edit` - The form for editing an existing resource
- `:show` - The detailed view of a single resource
- `:resource_action` - An open resource action on the list view

## Form Actions

When working with forms (in `:new` or  `:edit` live actions), the following form actions are available:

- `:save` - When a form is successfully submitted aka the "Save" button was clicked
- `:cancel` - When a form submission is canceled aka the "Cancel" button was clicked

For all other live actions, the form_action will be `nil`.

## Custom Form Actions

The buttons of the `:new` and `:edit` forms come from the
[form_actions/2](Backpex.LiveResource.html#c:form_actions/2) callback. It receives the assigns,
including the item being edited, and the default actions (`:save` and, with
`save_and_continue_button?: true`, `:continue`). Each action is a map with a `:label` and an
optional `soft: true` for a less prominent button.

Every action saves the form. The key of the clicked button arrives as `form_action` in
`return_to/5`, so a button can decide where the user goes next:

```elixir
# in your resource configuration file
@impl Backpex.LiveResource
def form_actions(%{live_action: :edit}, default_actions) do
  [{:show, %{label: "Save & Show", soft: true}} | default_actions]
end

def form_actions(_assigns, default_actions), do: default_actions

@impl Backpex.LiveResource
def return_to(socket, assigns, :edit, :show, item) do
  Router.get_path(socket, assigns.live_resource, assigns.params, :show, item)
end
```

Clauses of `return_to/5` you do not define fall back to the default destination. `:continue`
keeps its built-in behavior and stays on the form.

## Overriding the destination per link (`return_to`)

Sometimes the destination depends on where the user came from rather than on the
resource itself. For these cases you can append a `return_to` query parameter to
any `:new`, `:edit`, or `:show` URL. Backpex uses it as the navigation target
after the form is saved/canceled or after an item action completes, overriding
the default index/show path.

```elixir
# link into the show view and send the user back to a custom page afterwards
~p"/admin/posts/#{post}/show?return_to=/dashboard"
```

This is useful, for example, when a notification links to a resource and you want
the user to return to the notification list once they have acted on it.

Only same-origin, absolute paths are honored. Any value that carries a scheme or
host (`https://example.com`, `//example.com`, `/\example.com`) is ignored to
prevent open redirects, and Backpex falls back to the default destination. Paths
may include query strings (e.g. `/admin/posts?page=2`).
