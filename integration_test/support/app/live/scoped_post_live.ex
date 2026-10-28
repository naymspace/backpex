defmodule Backpex.Test.ScopedPostLive do
  @moduledoc """
  A LiveResource of the published posts only, with `c:Backpex.LiveResource.scope/1`. Its relation fields limit their
  options with `:options_filter`: the author to users whose username doesn't start with `"hidden"`, and the tags of the
  new form to the ones whose name doesn't start with `"Hidden"`.
  """
  use Backpex.LiveResource,
    adapter_config: [
      schema: Backpex.Test.Post,
      repo: Backpex.Test.Repo,
      update_changeset: &Backpex.Test.Post.update_changeset/3,
      create_changeset: &Backpex.Test.Post.create_changeset/3
    ]

  import Backpex.Expr

  @impl Backpex.LiveResource
  def layout(_assigns), do: {Backpex.Test.Layouts, :admin}

  @impl Backpex.LiveResource
  def singular_name, do: "Post"

  @impl Backpex.LiveResource
  def plural_name, do: "Posts"

  @impl Backpex.LiveResource
  def scope(_assigns), do: expr(published == true)

  @impl Backpex.LiveResource
  def fields do
    [
      title: %{module: Backpex.Fields.Text, label: "Title", searchable: true},
      user: %{
        module: Backpex.Fields.BelongsTo,
        label: "Author",
        display_field: :username,
        live_resource: Backpex.Test.UserLive,
        options_filter: expr(not starts_with(username, "hidden"))
      },
      tags: %{
        module: Backpex.Fields.HasMany,
        label: "Tags",
        display_field: :name,
        live_resource: Backpex.Test.TagLive,
        options_filter: fn assigns ->
          if assigns.live_action == :new, do: expr(not starts_with(name, "Hidden"))
        end
      }
    ]
  end
end
