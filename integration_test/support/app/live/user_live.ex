defmodule Backpex.Test.UserLive do
  @moduledoc """
  Users with integer primary keys. They have an `item_query` that hides soft-deleted users, an `init_order` function,
  a `can?/3` that denies the item action `Backpex.Test.ItemActions.UserSoftDelete` for admins, two resource actions, a
  panel, an index editable field, a HasManyThrough field with a pivot field and an InlineCRUD field of an embed.
  """
  use Backpex.LiveResource,
    adapter_config: [
      schema: Backpex.Test.User,
      repo: Backpex.Test.Repo,
      update_changeset: &Backpex.Test.User.changeset/3,
      create_changeset: &Backpex.Test.User.changeset/3,
      item_query: &__MODULE__.item_query/3
    ],
    init_order: &__MODULE__.init_order/1

  import Ecto.Query, warn: false

  @impl Backpex.LiveResource
  def layout(_assigns), do: {Backpex.Test.Layouts, :admin}

  @impl Backpex.LiveResource
  def singular_name, do: "User"

  @impl Backpex.LiveResource
  def plural_name, do: "Users"

  @impl Backpex.LiveResource
  def can?(_assigns, :user_soft_delete, item), do: item.role != :admin
  def can?(_assigns, _action, _item), do: true

  def item_query(query, _live_action, _assigns) do
    from u in query, where: is_nil(u.deleted_at)
  end

  def init_order(_assigns), do: %{by: :username, direction: :asc}

  @impl Backpex.LiveResource
  def resource_actions do
    [
      invite: %{module: Backpex.Test.ResourceActions.Email},
      upload: %{module: Backpex.Test.ResourceActions.Upload}
    ]
  end

  @impl Backpex.LiveResource
  def item_actions(default_actions) do
    default_actions
    |> Keyword.delete(:delete)
    |> Enum.concat(user_soft_delete: %{module: Backpex.Test.ItemActions.UserSoftDelete})
  end

  @impl Backpex.LiveResource
  def panels, do: [names: "Names"]

  @impl Backpex.LiveResource
  def fields do
    [
      username: %{
        module: Backpex.Fields.Text,
        label: "Username",
        searchable: true,
        panel: :names,
        index_editable: true
      },
      full_name: %{
        module: Backpex.Fields.Text,
        label: "Full Name",
        searchable: true,
        except: [:edit, :new],
        select: dynamic([user: u], fragment("concat(?, ' ', ?)", u.first_name, u.last_name)),
        panel: :names
      },
      first_name: %{
        module: Backpex.Fields.Text,
        label: "First Name",
        only: [:edit, :new],
        searchable: true,
        panel: :names
      },
      last_name: %{
        module: Backpex.Fields.Text,
        label: "Last Name",
        only: [:edit, :new],
        searchable: true,
        panel: :names
      },
      age: %{module: Backpex.Fields.Number, label: "Age"},
      role: %{module: Backpex.Fields.Select, label: "Role", options: [Admin: "admin", User: "user"]},
      posts: %{
        module: Backpex.Fields.HasMany,
        label: "Posts",
        display_field: :title,
        orderable: false,
        live_resource: Backpex.Test.PostLive
      },
      addresses: %{
        module: Backpex.Fields.HasManyThrough,
        label: "Addresses",
        display_field: :street,
        except: [:index],
        live_resource: Backpex.Test.AddressLive,
        pivot_fields: [
          type: %{
            module: Backpex.Fields.Select,
            label: "Address Type",
            options: [Shipping: "shipping", Billing: "billing"]
          }
        ]
      },
      social_links: %{
        module: Backpex.Fields.InlineCRUD,
        label: "Social links",
        type: :embed,
        except: [:index],
        child_fields: [
          label: %{module: Backpex.Fields.Text, label: "Label"},
          url: %{module: Backpex.Fields.Text, label: "URL"}
        ]
      }
    ]
  end
end
