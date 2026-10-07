---
name: create-item-action
description: Use when creating custom Backpex item actions, adding action buttons to table rows or the show page, or modifying the default edit/delete/show actions.
---

# Creating Backpex Item Actions

You are an expert at creating item actions for Backpex. Item actions operate on one or more selected items (rows) in the index view, or on a single item in the show view.

## Built-in Item Actions

| Module | Description |
|--------|-------------|
| `Backpex.ItemActions.Show` | Navigate to show page (uses `link/2`) |
| `Backpex.ItemActions.Edit` | Navigate to edit page (uses `link/2`) |
| `Backpex.ItemActions.Delete` | Delete selected items with confirmation (uses `handle/3`) |

Default placements:
- `show`: row only
- `edit`: row + show page
- `delete`: row + index toolbar + show page

## Creating a Custom Item Action

Use `use BackpexWeb, :item_action` to set up the behaviour.

### Required Callbacks

| Callback | Signature | Notes |
|----------|-----------|-------|
| `icon/2` | `(assigns, item) -> HEEx` | Action button icon |
| `label/2` | `(assigns, item) -> string` | Tooltip text. `item` is `nil` for index-placement buttons |
| One of `handle/3` or `link/2` | | Exactly one must be defined |

### `handle/3` vs `link/2`

- **`handle/3`**: Server-side action. Receives `(socket, items, params)`. Returns `{:ok, socket}` or `{:error, changeset}` (only with form fields).
- **`link/2`**: Client-side navigation. Receives `(assigns, item)`. Returns a URL string. Enables Ctrl+click.

Defining both raises a `CompileError`.

### Optional Callbacks

| Callback | Default | Notes |
|----------|---------|-------|
| `fields/0` | `[]` | Field definitions for a form modal |
| `confirm/1` | none | Confirmation text. **Required** when `fields/0` is non-empty |
| `confirm_label/1` | `"Apply"` | Confirm button text |
| `cancel_label/1` | `"Cancel"` | Cancel button text |
| `changeset/3` | none | **Required** when `fields/0` is non-empty |
| `base_schema/1` | schemaless changeset | Override to seed form with existing data |

### Example: Simple Action Without Form

```elixir
defmodule MyAppWeb.ItemActions.ArchivePost do
  use BackpexWeb, :item_action

  import Ecto.Query

  alias MyApp.Repo

  @impl Backpex.ItemAction
  def icon(assigns, _item) do
    ~H"""
    <Backpex.HTML.CoreComponents.icon name="hero-archive-box" class="h-5 w-5" />
    """
  end

  @impl Backpex.ItemAction
  def label(_assigns, nil), do: "Archive"
  def label(_assigns, item), do: "Archive #{item.title}"

  @impl Backpex.ItemAction
  def confirm(_assigns), do: "Are you sure you want to archive the selected items?"

  @impl Backpex.ItemAction
  def confirm_label(_assigns), do: "Archive"

  @impl Backpex.ItemAction
  def handle(socket, items, _params) do
    ids = Enum.map(items, & &1.id)

    from(p in MyApp.Post, where: p.id in ^ids)
    |> Repo.update_all(set: [archived_at: DateTime.utc_now(:second)])

    {:ok, Phoenix.LiveView.put_flash(socket, :info, "Items archived.")}
  end
end
```

### Example: Action With Form Fields

```elixir
defmodule MyAppWeb.ItemActions.DuplicatePost do
  use BackpexWeb, :item_action

  import Ecto.Changeset

  alias MyApp.Repo

  @impl Backpex.ItemAction
  def icon(assigns, _item) do
    ~H"""
    <Backpex.HTML.CoreComponents.icon name="hero-document-duplicate" class="h-5 w-5" />
    """
  end

  @impl Backpex.ItemAction
  def label(_assigns, nil), do: "Duplicate"
  def label(_assigns, item), do: "Duplicate #{item.title}"

  @impl Backpex.ItemAction
  def fields do
    [
      title: %{
        module: Backpex.Fields.Text,
        label: "New Title"
      }
    ]
  end

  @impl Backpex.ItemAction
  def confirm(_assigns), do: "Enter a title for the duplicate."

  @impl Backpex.ItemAction
  def confirm_label(_assigns), do: "Duplicate"

  @impl Backpex.ItemAction
  def base_schema(assigns) do
    [item | _] = assigns.selected_items
    item
  end

  @impl Backpex.ItemAction
  def changeset(item, attrs, _metadata) do
    item
    |> cast(attrs, [:title])
    |> validate_required([:title])
  end

  @impl Backpex.ItemAction
  def handle(socket, _items, data) do
    attrs = Map.from_struct(data) |> Map.drop([:id, :inserted_at, :updated_at])

    case Repo.insert(MyApp.Post.changeset(%MyApp.Post{}, attrs, [])) do
      {:ok, _post} -> {:ok, Phoenix.LiveView.put_flash(socket, :info, "Post duplicated.")}
      {:error, _} -> {:ok, Phoenix.LiveView.put_flash(socket, :error, "Failed to duplicate.")}
    end
  end
end
```

### Example: Navigation Action (link)

```elixir
defmodule MyAppWeb.ItemActions.ViewOnSite do
  use BackpexWeb, :item_action

  @impl Backpex.ItemAction
  def icon(assigns, _item) do
    ~H"""
    <Backpex.HTML.CoreComponents.icon name="hero-arrow-top-right-on-square" class="h-5 w-5" />
    """
  end

  @impl Backpex.ItemAction
  def label(_assigns, _item), do: "View on site"

  @impl Backpex.ItemAction
  def link(_assigns, item), do: "/posts/#{item.slug}"
end
```

## Wiring Into a LiveResource

The `item_actions/1` callback receives the default actions (show, edit, delete) and returns a modified keyword list.

```elixir
@impl Backpex.LiveResource
def item_actions(default_actions) do
  default_actions
  |> Keyword.delete(:delete)
  |> Enum.concat(
    archive: %{module: MyAppWeb.ItemActions.ArchivePost, only: [:row, :index]},
    duplicate: %{module: MyAppWeb.ItemActions.DuplicatePost, only: [:row, :show]}
  )
end
```

### Placement Options

| Placement | Description |
|-----------|-------------|
| `:row` | Icon button in each table row |
| `:index` | Button in index toolbar (acts on selected items) |
| `:show` | Button on the show/detail page |

Use `only: [...]` or `except: [...]` in the action map to control placement.

## Conventions

- **File location**: `lib/my_app_web/item_actions/<snake_case_name>.ex`
- **Module naming**: `MyAppWeb.ItemActions.<ActionName>`
- **Always handle `nil` item** in `label/2` (for index-placement buttons)
- **Include a `type:` key** in field maps when using schemaless changesets (no `base_schema/1` override)
- **Authorization** is handled via `can?/3` in the LiveResource, using the action's keyword key as the action name
