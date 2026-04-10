---
name: create-live-resource
description: Use when scaffolding a new Backpex LiveResource, setting up admin CRUD views, or configuring adapter_config, fields, filters, and routing for a resource.
---

# Creating a Backpex LiveResource

You are an expert at creating LiveResources for Backpex. When the user wants to create a new admin resource, follow this process:

1. **Identify the Ecto schema** the resource will manage
2. **Generate the LiveResource module** with adapter_config, fields, and callbacks
3. **Add the route** to the router

## LiveResource Module Structure

```elixir
defmodule MyAppWeb.PostLive do
  use Backpex.LiveResource,
    adapter_config: [
      schema: MyApp.Post,
      repo: MyApp.Repo,
      update_changeset: &MyApp.Post.changeset/3,
      create_changeset: &MyApp.Post.changeset/3
    ]

  @impl Backpex.LiveResource
  def layout(_assigns), do: {MyAppWeb.Layouts, :admin}

  @impl Backpex.LiveResource
  def singular_name, do: "Post"

  @impl Backpex.LiveResource
  def plural_name, do: "Posts"

  @impl Backpex.LiveResource
  def fields do
    [
      title: %{
        module: Backpex.Fields.Text,
        label: "Title",
        searchable: true
      }
    ]
  end
end
```

## `use Backpex.LiveResource` Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `adapter_config` | keyword | **required** | Ecto adapter configuration (see below) |
| `adapter` | atom | `Backpex.Adapters.Ecto` | Data layer adapter |
| `primary_key` | atom | `:id` | Primary key field |
| `per_page_options` | list | `[15, 50, 100]` | Selectable page sizes |
| `per_page_default` | integer | `15` | Default page size |
| `init_order` | map or fn | `%{by: :id, direction: :asc}` | Initial sort order |
| `fluid?` | boolean | `false` | Full-width layout |
| `full_text_search` | atom | `nil` | PostgreSQL tsvector column name |
| `save_and_continue_button?` | boolean | `false` | Show "Save & Continue" button |
| `pubsub` | keyword | nil (falls back to `:backpex, :pubsub_server` app config, topic defaults to module name) | `[server: MyApp.PubSub]` |
| `on_mount` | atom/list | nil | LiveView on_mount hooks |

## adapter_config (Ecto)

| Key | Required | Description |
|-----|----------|-------------|
| `schema` | yes | Ecto schema module |
| `repo` | yes | Ecto repo module |
| `update_changeset` | no | `fn item, attrs, metadata -> changeset` |
| `create_changeset` | no | `fn item, attrs, metadata -> changeset` |
| `item_query` | no | `fn query, live_action, assigns -> query` |

The `metadata` keyword list contains `:assigns` and `:target` (the form field that triggered the change).

The `item_query` function must build on the incoming `query` argument (use `from p in query, ...`), not the schema directly.

## Required Callbacks

| Callback | Returns | Description |
|----------|---------|-------------|
| `singular_name/0` | string | e.g. `"Post"` |
| `plural_name/0` | string | e.g. `"Posts"` |
| `fields/0` | keyword list | Field definitions |
| `layout/1` | `{module, :function}` or `fn assigns -> ...` | Layout to use |

## Optional Callbacks

| Callback | Default | Description |
|----------|---------|-------------|
| `can?/3` | always true | `fn assigns, action, item -> bool` |
| `filters/0` | `[]` | Filter definitions |
| `filters/1` | delegates to `filters/0` | Assigns-aware variant for dynamic filters |
| `panels/0` | `[]` | Field grouping: `[key: "Label"]` |
| `metrics/0` | `[]` | Index page metrics |
| `resource_actions/0` | `[]` | Resource-level actions |
| `item_actions/1` | returns default_actions unchanged | Modify default item actions |
| `on_item_created/2` | noop | `fn socket, item -> socket` |
| `on_item_updated/2` | noop | `fn socket, item -> socket` |
| `on_item_deleted/2` | noop | `fn socket, item -> socket` |
| `return_to/5` | index page | Custom redirect after save |
| `index_row_class/4` | nil | Custom CSS for table rows |
| `render_resource_slot/3` | default HTML | Override UI slots |
| `translate/1` | delegates to `Backpex.translate/1` | Override UI strings |

## Router Setup

```elixir
import Backpex.Router

scope "/admin", MyAppWeb do
  pipe_through :browser

  backpex_routes()

  live_session :admin, on_mount: Backpex.InitAssigns do
    live_resources "/posts", PostLive
    live_resources "/users", UserLive
    live_resources "/categories", CategoryLive, only: [:index, :show]
  end
end
```

`backpex_routes()` must appear once per scope. `live_resources/3` generates routes for Index, Form (new/edit), and Show views.

Options for `live_resources/3`:
- `only: [:index, :show, :new, :edit]` to restrict routes
- `except: [:new]` to exclude specific routes

## Complete Example

```elixir
defmodule MyAppWeb.ProductLive do
  use Backpex.LiveResource,
    adapter_config: [
      schema: MyApp.Product,
      repo: MyApp.Repo,
      update_changeset: &MyApp.Product.changeset/3,
      create_changeset: &MyApp.Product.changeset/3,
      item_query: &__MODULE__.item_query/3
    ],
    per_page_default: 25,
    init_order: %{by: :inserted_at, direction: :desc}

  import Ecto.Query

  @impl Backpex.LiveResource
  def layout(_assigns), do: {MyAppWeb.Layouts, :admin}

  @impl Backpex.LiveResource
  def singular_name, do: "Product"

  @impl Backpex.LiveResource
  def plural_name, do: "Products"

  @impl Backpex.LiveResource
  def panels do
    [details: "Details", metadata: "Metadata"]
  end

  @impl Backpex.LiveResource
  def fields do
    [
      name: %{
        module: Backpex.Fields.Text,
        label: "Name",
        searchable: true,
        panel: :details
      },
      price: %{
        module: Backpex.Fields.Currency,
        label: "Price",
        panel: :details
      },
      category: %{
        module: Backpex.Fields.BelongsTo,
        label: "Category",
        display_field: :name,
        live_resource: MyAppWeb.CategoryLive,
        panel: :details
      },
      published: %{
        module: Backpex.Fields.Boolean,
        label: "Published",
        index_editable: true
      },
      inserted_at: %{
        module: Backpex.Fields.DateTime,
        label: "Created At",
        only: [:index, :show],
        panel: :metadata
      }
    ]
  end

  @impl Backpex.LiveResource
  def can?(_assigns, :delete, item), do: not item.published
  def can?(_assigns, _action, _item), do: true

  def item_query(query, _live_action, _assigns) do
    from p in query, where: is_nil(p.archived_at)
  end
end
```

## Conventions

- **File location**: `lib/my_app_web/live/<resource>_live.ex`
- **Module naming**: `MyAppWeb.<Resource>Live` (e.g. `MyAppWeb.ProductLive`)
- **Changeset functions** should accept 3 arguments: `item`, `attrs`, `metadata`
- **Use `layout/1` callback** instead of the `layout:` option (avoids compile-time dependencies)
- **Always build on the incoming query** in `item_query/3`
