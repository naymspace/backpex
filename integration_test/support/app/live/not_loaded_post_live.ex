defmodule Backpex.Test.NotLoadedPostLive do
  @moduledoc """
  A LiveResource of the published posts with `c:Backpex.LiveResource.scope/1`, `c:Backpex.LiveResource.load/1` and
  `c:Backpex.LiveResource.computed/1`, which tests unload to check that Backpex loads a LiveResource before looking at
  these callbacks. It has no route and no other test uses it, so unloading it doesn't affect them.
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
  def load(_assigns),
    do: [user: Backpex.Query.related(computed: [full_name: expr(concat([first_name, last_name], " "))])]

  @impl Backpex.LiveResource
  def computed(_assigns), do: [headline: expr(concat([title, "!"], ""))]

  @impl Backpex.LiveResource
  def fields do
    [
      title: %{module: Backpex.Fields.Text, label: "Title"},
      user: %{
        module: Backpex.Fields.BelongsTo,
        label: "Author",
        display_field: :full_name,
        options_sort: [full_name: :desc]
      }
    ]
  end
end
