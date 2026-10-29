# Hooks

You may define hooks that are called before and after an item is created, updated or deleted.

| Action | Before the change is saved | After the change is saved |
| --- | --- | --- |
| create | [on_item_creating/2](Backpex.LiveResource.html#c:on_item_creating/2) | [on_item_created/2](Backpex.LiveResource.html#c:on_item_created/2) |
| update | [on_item_updating/2](Backpex.LiveResource.html#c:on_item_updating/2) | [on_item_updated/2](Backpex.LiveResource.html#c:on_item_updated/2) |
| delete | [on_item_deleting/2](Backpex.LiveResource.html#c:on_item_deleting/2) | [on_item_deleted/2](Backpex.LiveResource.html#c:on_item_deleted/2) |

Backpex calls the hooks when an item is saved with the form, edited inline on the index view or deleted with the built-in delete item action. Each hook receives the socket of the view or component that saves the item. The before hooks are only called after the user is authorized to perform the action, see `c:Backpex.LiveResource.can?/3`.

## Before Hooks

### Creating and Updating Items

`on_item_creating/2` and `on_item_updating/2` receive the change that the adapter built from the form and must return a change of the same type. With the Ecto adapter, this is the `Ecto.Changeset` of your `create_changeset` or `update_changeset` function. Backpex saves the change that the hook returns.

Your changeset functions are also called while the user fills in the form, so use the before hooks for changes that should only be made when the item is saved, for example a change that depends on the current user or on data that is expensive to read.

```elixir
# in your resource configuration file

@impl Backpex.LiveResource
def on_item_creating(socket, changeset) do
  Ecto.Changeset.put_change(changeset, :author_id, socket.assigns.current_scope.user.id)
end

@impl Backpex.LiveResource
def on_item_updating(socket, changeset) do
  Ecto.Changeset.put_change(changeset, :editor_id, socket.assigns.current_scope.user.id)
end
```

To cancel the save, add an error to the change. The adapter then refuses to save it and the form shows the error. Add the error to a field of the form, so it is shown next to the field. An error on another key, for example `:base` or a field that is not in the form, is not shown; the form only says that it has errors. An inline edit on the index view does not show the error either, it only marks the field as invalid. With the Ecto adapter, the item before the update is the `data` of the changeset.

```elixir
@impl Backpex.LiveResource
def on_item_updating(_socket, changeset) do
  if MyApp.Blog.published?(changeset.data) and Ecto.Changeset.changed?(changeset, :slug) do
    Ecto.Changeset.add_error(changeset, :slug, "can't be changed after the post was published")
  else
    changeset
  end
end
```

> #### Warning {: .warning}
>
> The change may already be invalid when the hook is called, and the adapter may still refuse to save it afterwards, for example because of a database constraint. Do not run side effects in these hooks directly. With the Ecto adapter, use `Ecto.Changeset.prepare_changes/2`: its function is only called for a valid changeset, in the same transaction that saves the item. Use the after hooks for side effects that should only happen once the item is saved.

```elixir
@impl Backpex.LiveResource
def on_item_updating(socket, changeset) do
  user = socket.assigns.current_scope.user

  Ecto.Changeset.prepare_changes(changeset, fn changeset ->
    changeset.repo.insert!(MyApp.AuditLog.changeset(user, changeset))
    changeset
  end)
end
```

### Deleting Items

`on_item_deleting/2` is called for each item before the delete item action deletes the selected items. Return `:ok` to delete the item, or `{:error, message}` to cancel the deletion. Backpex then deletes none of the selected items and shows the message.

```elixir
@impl Backpex.LiveResource
def on_item_deleting(_socket, category) do
  case MyApp.Blog.count_posts(category) do
    0 -> :ok
    count -> {:error, "#{category.name} can't be deleted, because #{count} posts belong to it."}
  end
end
```

Backpex stops at the first item that may not be deleted. The hook may then already have been called for other selected items, which are not deleted either, so use `on_item_deleted/2` for side effects. When the deletion of an item is refused on its show view, the user stays on the show view.

The hook is called once per selected item, so a check that reads the database runs one query per item. Keep it cheap, as users may delete many items at once.

Backpex does not rescue exceptions raised in the hook. Return `{:error, message}` for every case in which the user should see a message.

## After Hooks

The after hooks are called with the saved item after the changes have been persisted to the database. Their return value is not used.

```elixir
@impl Backpex.LiveResource
def on_item_created(socket, item) do
  MyApp.Notifications.item_created(item, socket.assigns.current_scope)
  socket
end
```

When an item is saved with the form, the item before the update is still in the `item` assign of the socket that `on_item_updated/2` receives.

## Custom Code

The hooks are not called by `Backpex.Resource`. If you save items with `Backpex.Resource.insert/6` or `Backpex.Resource.update/6` in your own code, for example in a custom field, pass the `:before_save_fun` and `:after_save_fun` options to call them:

```elixir
Backpex.Resource.update(item, change, fields, assigns, live_resource,
  before_save_fun: &live_resource.on_item_updating(socket, &1),
  after_save_fun: fn item ->
    live_resource.on_item_updated(socket, item)
    {:ok, item}
  end
)
```

`Backpex.Resource.update_all/5` and `Backpex.Resource.delete_all/4` never call the hooks. `update_all/5` receives update instructions for the adapter instead of a change, so there is nothing to pass to `on_item_updating/2`. A custom item action that saves items with these functions, for example to soft delete them, skips the rules in your before hooks. Check them in the item action, for example in `c:Backpex.ItemAction.handle/3`.
