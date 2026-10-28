defmodule Backpex.Test.UserRelationOptionsLive do
  @moduledoc """
  A LiveResource of users whose relation fields set the options that `Backpex.Test.UserLive` leaves at their defaults:
  `display_field_form` of `Backpex.Fields.HasMany` and `sort_by` of `Backpex.Fields.HasManyThrough`.
  """
  use Backpex.LiveResource,
    adapter_config: [
      schema: Backpex.Test.User,
      repo: Backpex.Test.Repo,
      update_changeset: &Backpex.Test.User.changeset/3,
      create_changeset: &Backpex.Test.User.changeset/3
    ]

  @impl Backpex.LiveResource
  def layout(_assigns), do: {Backpex.Test.Layouts, :admin}

  @impl Backpex.LiveResource
  def singular_name, do: "User"

  @impl Backpex.LiveResource
  def plural_name, do: "Users"

  @impl Backpex.LiveResource
  def fields do
    [
      username: %{module: Backpex.Fields.Text, label: "Username"},
      posts: %{
        module: Backpex.Fields.HasMany,
        label: "Posts",
        display_field: :title,
        display_field_form: :body,
        live_resource: Backpex.Test.PostLive
      },
      addresses: %{
        module: Backpex.Fields.HasManyThrough,
        label: "Addresses",
        display_field: :street,
        except: [:index],
        live_resource: Backpex.Test.AddressLive,
        sort_by: [:city],
        pivot_fields: [
          type: %{
            module: Backpex.Fields.Select,
            label: "Address Type",
            options: [Shipping: "shipping", Billing: "billing"]
          }
        ]
      }
    ]
  end
end
