---
name: create-resource-action
description: Use when creating Backpex resource actions for global operations like bulk exports, invitations, imports, or any action that applies to the resource as a whole rather than individual items.
---

# Creating Backpex Resource Actions

You are an expert at creating resource actions for Backpex. Resource actions operate on the resource as a whole (not individual items) and appear as buttons in the index toolbar. They open a slide-over with a form.

## Required Callbacks

| Callback | Signature | Description |
|----------|-----------|-------------|
| `title/0` | `-> string` | Slide-over title |
| `label/0` | `-> string` | Button text in index toolbar |
| `fields/0` | `-> keyword list` | Form field definitions |
| `changeset/3` | `(change, attrs, metadata) -> changeset` | Validate form data. `metadata` has `:assigns` and `:target` keys |
| `handle/2` | `(socket, data) -> {:ok, socket} \| {:error, changeset}` | Execute the action with validated data |

## Optional Callbacks

| Callback | Default | Description |
|----------|---------|-------------|
| `base_schema/1` | schemaless changeset | Override to use a real Ecto schema |

## Example: Simple Resource Action

```elixir
defmodule MyAppWeb.ResourceActions.InviteUser do
  use Backpex.ResourceAction

  import Ecto.Changeset

  @impl Backpex.ResourceAction
  def title, do: "Invite User"

  @impl Backpex.ResourceAction
  def label, do: "Invite"

  @impl Backpex.ResourceAction
  def fields do
    [
      email: %{
        module: Backpex.Fields.Text,
        label: "Email",
        type: :string
      },
      role: %{
        module: Backpex.Fields.Select,
        label: "Role",
        options: [Admin: "admin", User: "user"],
        prompt: "Select role...",
        type: :string
      }
    ]
  end

  @impl Backpex.ResourceAction
  def changeset(change, attrs, _metadata) do
    change
    |> cast(attrs, [:email, :role])
    |> validate_required([:email, :role])
    |> validate_format(:email, ~r/@/)
  end

  @impl Backpex.ResourceAction
  def handle(socket, data) do
    case MyApp.Accounts.send_invitation(data.email, data.role) do
      :ok ->
        {:ok, Phoenix.LiveView.put_flash(socket, :info, "Invitation sent to #{data.email}.")}

      {:error, reason} ->
        {:ok, Phoenix.LiveView.put_flash(socket, :error, "Failed: #{reason}")}
    end
  end
end
```

## Example: Export Action

```elixir
defmodule MyAppWeb.ResourceActions.ExportPosts do
  use Backpex.ResourceAction

  import Ecto.Changeset

  @impl Backpex.ResourceAction
  def title, do: "Export Posts"

  @impl Backpex.ResourceAction
  def label, do: "Export"

  @impl Backpex.ResourceAction
  def fields do
    [
      format: %{
        module: Backpex.Fields.Select,
        label: "Format",
        options: [CSV: "csv", JSON: "json"],
        prompt: "Select format...",
        type: :string
      }
    ]
  end

  @impl Backpex.ResourceAction
  def changeset(change, attrs, _metadata) do
    change
    |> cast(attrs, [:format])
    |> validate_required([:format])
    |> validate_inclusion(:format, ["csv", "json"])
  end

  @impl Backpex.ResourceAction
  def handle(socket, data) do
    # Trigger export...
    {:ok, Phoenix.LiveView.put_flash(socket, :info, "Export started in #{data.format} format.")}
  end
end
```

## Wiring Into a LiveResource

```elixir
@impl Backpex.LiveResource
def resource_actions do
  [
    invite: %{module: MyAppWeb.ResourceActions.InviteUser},
    export: %{module: MyAppWeb.ResourceActions.ExportPosts}
  ]
end
```

The keyword key (e.g. `:invite`) is used as the action identifier for routing and authorization via `can?/3`.

## Key Differences From Item Actions

| Aspect | Resource Action | Item Action |
|--------|----------------|-------------|
| Scope | Whole resource | Selected items |
| UI | Slide-over form | Modal dialog |
| Callbacks | `title/0`, `label/0`, `handle/2` | `icon/2`, `label/2`, `handle/3` |
| Form | Always has fields | Optional |
| Location | Index toolbar only | Row, index toolbar, show page |

## Conventions

- **File location**: `lib/my_app_web/resource_actions/<snake_case_name>.ex`
- **Module naming**: `MyAppWeb.ResourceActions.<ActionName>`
- **Always include `type:` key** in each field map (e.g. `type: :string`). This is required for the schemaless changeset to work.
- **Authorization** is handled via `can?(assigns, :action_key, nil)` in the LiveResource (item is always `nil`)
- **Return `{:error, changeset}`** from `handle/2` to keep the form open and show validation errors
