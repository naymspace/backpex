defmodule Backpex.Test.PostRelationOptionsLive do
  @moduledoc """
  A LiveResource of posts whose relation fields set the options that `Backpex.Test.PostLive` leaves at their defaults:
  `display_field_form` of `Backpex.Fields.BelongsTo` and `link_assocs`, `prompt` and `not_found_text` of
  `Backpex.Fields.HasMany`.
  """
  use Backpex.LiveResource,
    adapter_config: [
      schema: Backpex.Test.Post,
      repo: Backpex.Test.Repo,
      update_changeset: &Backpex.Test.Post.update_changeset/3,
      create_changeset: &Backpex.Test.Post.create_changeset/3
    ]

  @impl Backpex.LiveResource
  def layout(_assigns), do: {Backpex.Test.Layouts, :admin}

  @impl Backpex.LiveResource
  def singular_name, do: "Post"

  @impl Backpex.LiveResource
  def plural_name, do: "Posts"

  @impl Backpex.LiveResource
  def fields do
    [
      title: %{module: Backpex.Fields.Text, label: "Title"},
      user: %{
        module: Backpex.Fields.BelongsTo,
        label: "Author",
        display_field: :username,
        display_field_form: :first_name,
        live_resource: Backpex.Test.UserLive
      },
      tags: %{
        module: Backpex.Fields.HasMany,
        label: "Tags",
        display_field: :name,
        live_resource: Backpex.Test.TagLive,
        link_assocs: false,
        prompt: "Pick some tags",
        not_found_text: "No tags match"
      }
    ]
  end
end
