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

## Enforcement

Backpex enforces `can?/3` centrally, through `Backpex.Authorization`. You do not need to repeat the check in your own actions.

There are two kinds of checks, and both run:

- **Preflight** — decides whether a control is rendered or disabled. A user never sees a button for something they may not do.
- **Gate** — runs immediately before something happens and raises `Backpex.ForbiddenError` when it fails. This is what makes a forged or stale event safe.

> #### What a denial looks like {: .info}
>
> `Backpex.ForbiddenError` and `Backpex.NoResultsError` carry a `plug_status` of 403 and 404, but Phoenix LiveView only maps that to an HTTP status while a view **mounts** — the dead render. Raised from an event handler on a connected socket (which is where the item and resource action gates live), the LiveView process crashes and the client reloads the page. The user gets no error page and no flash message.
>
> That is the intended outcome: the point of a gate is that the write does not happen. Do not rely on it to communicate anything — a user should never reach a gate through the UI in the first place, because the preflight checks already hid or disabled the control.

### Where the gates are

| what happens | action checked | item |
| --- | --- | --- |
| `:index` / `:show` view mounts | `:index` / `:show` | the item, for `:show` |
| `:new` / `:edit` form mounts | `:new` / `:edit` | the item, for `:edit` |
| `Backpex.Resource.insert/6` | `:new` | `nil` |
| `Backpex.Resource.update/6` | `:edit` | the item |
| `Backpex.Resource.update_all/5` | `:edit` | each item |
| `Backpex.Resource.delete_all/4` | `:delete` | each item |
| item action without a confirm modal, before `handle/3` runs | the action key | each selected item |
| item action with a confirm modal, on open and on submit | the action key | each selected item |
| resource action, on open and on submit | the action key | `nil` |

The `Backpex.Resource` gates run **before** the changeset is built and before `c:Backpex.Field.before_changeset/6` is called, so your own code never executes for an unauthorized request.

Each gesture runs exactly one gate per step, so `can?/3` is not evaluated more times than there are decisions to make. A modal flow has two steps on purpose: the second check catches a permission revoked, or a selection widened, while the modal was open.

### Strict semantics

Checks over a selection are strict: a single unauthorized item raises, and nothing runs. Backpex does not silently drop items from a selection.

A `nil` item — a stale or forged id — raises `Backpex.NoResultsError` and never reaches your `can?/3`, so you do not need clauses for it.

Because a mixed selection would raise, the bulk action button is disabled whenever the selection is empty or contains any unauthorized item. A row that is authorized for none of the bulk actions cannot be selected at all — its checkbox is disabled, so a user cannot build a selection that has no usable action.

### What `handle/3` may assume

The items handed to `c:Backpex.ItemAction.handle/3` have already been authorized under that action's key. Writing exactly those items back is the same decision the gate just made, so pass `authorize?: false` rather than paying for a second evaluation of your `can?/3`:

```elixir
Backpex.Resource.delete_all(items, socket.assigns, socket.assigns.live_resource, authorize?: false)
```

The guarantee covers only those items under that key. Writes to *other* items or to another resource keep the default gate.

### Overriding the action and the escape hatch

Every `Backpex.Resource` mutation accepts two options:

- `:authorization_action` — authorize against this action instead of the default. It must be a non-nil atom. Item actions can pass `socket.assigns.item_action_key`, so an action registered under a custom key is authorized under that key. Backpex sets that assign just before calling `c:Backpex.ItemAction.handle/3` and clears it again when the call returns, so it is meaningful for exactly one dispatch.
- `authorize?: false` — skip the check. Use this for a write the gate already covered (see above), and for system or cascade writes that are not a user-initiated action on the resource being written, for example nullifying a foreign key on another resource.

```elixir
Backpex.Resource.update_all(item.posts, [set: [user_id: nil]], socket.assigns, MyAppWeb.PostLive,
  event_name: "updated",
  authorize?: false
)
```

### Reads are not gated in `Backpex.Resource`

`Backpex.Resource.list/4`, `get/4` and `count/4` do not call `can?/3`. Row-level read filtering belongs in [`item_query/3`](item-query.html) — dropping rows after pagination would corrupt item counts and select-all. `:index` and `:show` are enforced when the view mounts.

### Calling the checks yourself

If you build your own UI on top of Backpex, use `Backpex.Authorization` rather than calling `can?/3` directly:

```elixir
Backpex.Authorization.can?(live_resource, assigns, :edit, item)
Backpex.Authorization.can_all?(live_resource, assigns, :delete, items)
Backpex.Authorization.authorize!(live_resource, assigns, :edit, item)
Backpex.Authorization.authorize_all!(live_resource, assigns, :delete, items)
```