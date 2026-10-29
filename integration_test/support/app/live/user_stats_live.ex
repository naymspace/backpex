defmodule Backpex.Test.UserStatsLive do
  @moduledoc """
  Users with computed values of their posts: aggregates over a relationship to many items, with a `:where`, a `:value`
  and a `:sort`, over the path `posts.tags`, aggregates that share a join and arithmetic of aggregates.
  """
  use Backpex.LiveResource,
    adapter_config: [
      schema: Backpex.Test.User,
      repo: Backpex.Test.Repo,
      update_changeset: &Backpex.Test.User.changeset/3,
      create_changeset: &Backpex.Test.User.changeset/3
    ],
    init_order: %{by: :username, direction: :asc}

  import Backpex.Expr

  @impl Backpex.LiveResource
  def layout(_assigns), do: {Backpex.Test.Layouts, :admin}

  @impl Backpex.LiveResource
  def singular_name, do: "User"

  @impl Backpex.LiveResource
  def plural_name, do: "Users"

  @impl Backpex.LiveResource
  def computed(_assigns) do
    [
      post_count: aggregate(:count, :posts),
      published_count: aggregate(:count, :posts, where: expr(published == true)),
      total_likes: aggregate(:sum, :posts, value: expr(likes)),
      top_post: aggregate(:first, :posts, value: expr(title), sort: [likes: :desc]),
      # Shares the join of `top_post`, as it only differs in the value.
      top_post_likes: aggregate(:first, :posts, value: expr(likes), sort: [likes: :desc]),
      draft_count: expr(^aggregate(:count, :posts) - ^aggregate(:count, :posts, where: expr(published == true))),
      first_tag: aggregate(:first, [:posts, :tags], value: expr(name), sort: [name: :asc])
    ]
  end

  @impl Backpex.LiveResource
  def fields do
    [
      username: %{module: Backpex.Fields.Text, label: "Username"},
      post_count: %{module: Backpex.Fields.Number, label: "Posts"},
      published_count: %{module: Backpex.Fields.Number, label: "Published"},
      total_likes: %{module: Backpex.Fields.Number, label: "Likes"},
      top_post: %{module: Backpex.Fields.Text, label: "Top post", searchable: true},
      top_post_likes: %{module: Backpex.Fields.Number, label: "Top post likes"},
      draft_count: %{module: Backpex.Fields.Number, label: "Drafts"},
      first_tag: %{module: Backpex.Fields.Text, label: "First tag"}
    ]
  end
end
