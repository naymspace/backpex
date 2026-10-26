defmodule Backpex.Test.Filters.PostCategorySelect do
  @moduledoc """
  Implementation of the `Backpex.Filters.MultiSelect` behaviour.
  """

  use Backpex.Filters.Select

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
