defmodule Backpex.Test.UserRelationOptionsLive do
  @moduledoc """
  A LiveResource of users whose relation fields set the options that `Backpex.Test.UserLive` leaves at their defaults:
  `display_field_form` and browser search (`searchable_options: true`) of `Backpex.Fields.HasMany`, and `sort_by`, an
  `options_query` that only offers German addresses and server search with a `query_limit` of 2 of
  `Backpex.Fields.HasManyThrough`.

  The `url` child field of `Backpex.Fields.InlineCRUD` is readonly.
  """
  use Backpex.LiveResource,
    adapter_config: [
      schema: Backpex.Test.User,
      repo: Backpex.Test.Repo,
      update_changeset: &Backpex.Test.User.changeset/3,
      create_changeset: &Backpex.Test.User.changeset/3
    ]

  import Ecto.Query

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
        searchable_options: true,
        live_resource: Backpex.Test.PostLive
      },
      addresses: %{
        module: Backpex.Fields.HasManyThrough,
        label: "Addresses",
        display_field: :street,
        except: [:index],
        live_resource: Backpex.Test.AddressLive,
        sort_by: [:city],
        options_query: fn query, _assigns ->
          query |> where([address], address.country == :de) |> order_by([address], address.street)
        end,
        searchable_options: :server,
        query_limit: 2,
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
        only: [:new, :edit],
        child_fields: [
          label: %{module: Backpex.Fields.Text, label: "Label"},
          url: %{module: Backpex.Fields.Text, label: "URL", readonly: true}
        ]
      }
    ]
  end
end
