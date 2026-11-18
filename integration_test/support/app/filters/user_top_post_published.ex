defmodule Backpex.Test.Filters.UserTopPostPublished do
  @moduledoc """
  A boolean filter on an aggregate: whether the post with the most likes of a user is published. The aggregate only
  differs in its value from the `top_post` of `Backpex.Test.UserStatsLive`.
  """

  use Backpex.Filters.Boolean

  alias Backpex.Filters.Boolean

  @impl Backpex.Filter
  def label, do: "Top post"

  @impl Boolean
  def options(_assigns) do
    top_post_published = Backpex.Expr.aggregate(:first, :posts, value: expr(published), sort: [likes: :desc])

    [%{label: "Published", key: "published", predicate: expr(^top_post_published == true)}]
  end
end
