# Item Actions

An item action defines an action (such as deleting a user) that can be performed on one or more items. Unlike resource actions, item actions are not automatically performed on all items in a resource.

An item action could be something like deleting a user, or sending an email to a specific user.

There are multiple ways to perform an Item Action:
- use the checkboxes in the first column of the resource table to select 1-n items and trigger the action later on
- use an icon in the last column of the resource table to perform the Item Action for one item

If you use the first method, you must trigger the item action using the button above the resource action. If you use the second method, the item action is triggered immediately.

Backpex ships with a few built-in item actions, such as `delete`, `show`, and `edit`.

## Configuration

To add an item action to a resource, you need to implement the [`item_actions/1`](Backpex.LiveResource.html#c:item_actions/1) callback in your resource configuration module. The function has to return a list of maps, where each map represents an item action. It takes the default item actions as an argument. This way you can add your custom item actions to the default ones or even replace them.

Let's say we want to add a `show` item action to navigate to the show view of a user and replace all other default item actions.

First, we need to add the item action to our resource configuration module.

```elixir
# in your resource configuration file
@impl Backpex.LiveResource
def item_actions([_show, _edit, _delete]) do
    [
        show: %{
            module: DemoWeb.ItemAction.Show
        }
    ]
end
```

In the above example, we only return the `show` item action. This way we replace the default `show`, `edit`, and `delete` item actions with our custom `show` item action.

## Implementing an Item Action

An item action is a module that uses the `Backpex.ItemAction` module. To get started, you can use the `BackpexWeb` module and provide the `:item_action` option. This will import the necessary functions and macros to define an item action.

In the following example, we define an item action to navigate to the show view of a user.

```elixir
defmodule DemoWeb.ItemAction.Show do
  use BackpexWeb, :item_action

  @impl Backpex.ItemAction
  def icon(assigns, _item) do
    ~H"""
    <Backpex.HTML.CoreComponents.icon name="hero-eye" class="h-5 w-5 cursor-pointer transition duration-75 hover:scale-110 hover:text-green-600" />
    """
  end

  @impl Backpex.ItemAction
  def label(_assigns, _item), do: "Show"

  @impl Backpex.ItemAction
  def handle(socket, [item | _items], _data) do
    path = Router.get_path(socket, socket.assigns.live_resource, socket.assigns.params, :show, item)
    {:ok, Phoenix.LiveView.push_patch(socket, to: path)}
  end
end
```

As with resource actions, the `c:Backpex.ItemAction.handle/3` function is called when the item action is triggered. The handle function receives the socket, the items to be affected by the action, and the parameters passed by the user.

In the example above, we define an item action to navigate to a user's show view. The function `c:Backpex.ItemAction.handle/3` is used to navigate to the corresponding view. The `Backpex.Router.get_path/6` function is used to generate the path needed.

The callbacks `c:Backpex.ItemAction.icon/2` and `c:Backpex.ItemAction.label/2` get the item on which the action is executed. You can use the item to customize this function depending on the item.

> #### Important {: .warning}
>
> Note that the item in the `c:Backpex.ItemAction.label/2` callback is nil if the callback is used to display the label of the item action button above the resource table or the label of the confirmation dialog. The item is present if the callback is used to determine the tooltip for the item action icon.
> 

See `Backpex.ItemAction` for a list of all available callbacks.

## Placement of Item Actions

Item actions can be placed in the index view on resource table, on top of it or in the show viw. You can specify the placement of the item action by using the `only` key.

The `only` key must provide a list and accepts the following options

* `:row` - display an icon for each element in the table that can trigger the Item Action for the corresponding element
* `:index` - display a button at the top of the resource table, which triggers the Item Action for selected items
* `:show` - display a icon at the top of the resource view, which triggers the Item Action for the corresponding element

The following example shows how to place the `show` item action on the index table rows only.

```elixir
# in your resource configuration file
@impl Backpex.LiveResource
def item_actions([_show, _edit, _delete]) do
    [
        show: %{
            module: DemoWeb.ItemAction.Show,
            only: [:row]
        }
    ]
end
```

## Advanced Item Action

In the following example, we define an item action to soft delete users. The item action will also asked the user for a reason before the user can be deleted.

First, wee need to add the item action to our resource configuration module.

```elixir
# in your resource configuration file

@impl Backpex.LiveResource
def item_actions([show, edit, _delete]) do
    Enum.concat([show, edit],
        soft_delete: %{module: DemoWeb.ItemAction.SoftDelete}
    )
end
```

In the above example, we add the `soft_delete` item action to the default item actions. We do not add the default `delete` item action to the list of item actions. This way we replace the default `delete` item action with our custom `soft_delete` item action.

Next, we need to implement the item action module.

```elixir
defmodule DemoWeb.ItemAction.SoftDelete do
    use BackpexWeb, :item_action

    import Ecto.Changeset

    alias Backpex.Resource

    @impl Backpex.ItemAction
    def icon(assigns, _item) do
    ~H"""
    <Backpex.HTML.CoreComponents.icon name="hero-eye" class="h-5 w-5 cursor-pointer transition duration-75 hover:scale-110 hover:text-green-600" />
    """
    end

    @impl Backpex.ItemAction
    def fields do
        [
            reason: %{
                module: Backpex.Fields.Textarea,
                label: "Reason",
                type: :string
            }
        ]       
    end

    @required_fields ~w[reason]a

    @impl Backpex.ItemAction
    def changeset(change, attrs, _meta) do
        change
        |> cast(attrs, @required_fields)
        |> validate_required(@required_fields)
    end

    @impl Backpex.ItemAction
    def confirm(_assigns), do: "Why do you want to delete this item?"

    @impl Backpex.ItemAction
    def label(_assigns, _item), do: "Delete"

    @impl Backpex.ItemAction
    def confirm_label(_assigns), do: "Delete"

    @impl Backpex.ItemAction
    def cancel_label(_assigns), do: "Cancel"

    @impl Backpex.ItemAction
    def handle(socket, items, data) do
        datetime = DateTime.truncate(DateTime.utc_now(), :second)

        socket =
            try do
                {:ok, _count_} =
                Backpex.Resource.update_all(
                    socket.assigns,
                    items,
                    [set: [deleted_at: datetime, reason: data.reason]],
                    "deleted"
                )

                socket
                |> clear_flash()
                |> put_flash(:info, "Item(s) successfully deleted.")
            rescue
                socket
                |> clear_flash()
                |> put_flash(:error, error)
            end

        {:ok, socket}
    end
end
```

In the above example, we define an item action to soft delete users. The item action will also ask the user for a reason before the user can be deleted. The user needs to fill out the reason field before the item action can be performed. The reason field is defined in the `c:Backpex.ItemAction.fields/0` function. The `c:Backpex.ItemAction.changeset/3` function is used to validate the user input.

The `c:Backpex.ItemAction.handle/3` function is called when the item action is triggered. The handle function receives the socket, the items that should be affected by the action, and the parameters that were submitted by the user.

By default an item action is triggered immediately when the user clicks on the corresponding icon in the resource table or in the show view, but an item actions also supports a confirmation dialog. To enable the confirmation dialog you need to implement the `c:Backpex.ItemAction.confirm/1` function and return a string that will be displayed in the confirmation dialog. The confirmation dialog will be displayed when the user clicks on the icon in the resource table.

You might want to use the `c:Backpex.ItemAction.cancel_label/1` (defaults to "Cancel") and `c:Backpex.ItemAction.confirm_label/1` (defaults to "Apply") functions to set the labels of the buttons in the dialog.
