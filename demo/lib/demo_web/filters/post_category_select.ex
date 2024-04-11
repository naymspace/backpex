defmodule DemoWeb.Filters.PostCategorySelect do
  @moduledoc """
  Implementation of the `Backpex.Filters.MultiSelect` behaviour.
  """

  use Backpex.Filters.Select

  alias Demo.Category
  alias Demo.Post
  alias Demo.Repo

  @impl Backpex.Filter
  def label, do: "Category"

  @impl Backpex.Filters.Select
  def prompt, do: "Select category ..."

  @impl Backpex.Filters.Select
  def options do
    query =
      from p in Post,
        join: c in Category,
        on: p.category_id == c.id,
        distinct: c.name,
        select: {c.name, c.id}

    Repo.all(query)
  end
end
