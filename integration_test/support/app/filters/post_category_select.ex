defmodule Backpex.Test.Filters.PostCategorySelect do
  @moduledoc "A select filter with the categories of the posts as options."

  use Backpex.Filters.Select

  import Ecto.Query

  alias Backpex.Filters.Select
  alias Backpex.Test.Category
  alias Backpex.Test.Post
  alias Backpex.Test.Repo

  @impl Backpex.Filter
  def label, do: "Category"

  @impl Select
  def prompt, do: "Select category ..."

  @impl Select
  def options(_assigns) do
    query =
      from p in Post,
        join: c in Category,
        on: p.category_id == c.id,
        distinct: c.name,
        select: {c.name, c.id}

    Repo.all(query)
  end
end
