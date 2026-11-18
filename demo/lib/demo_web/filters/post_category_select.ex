defmodule DemoWeb.Filters.PostCategorySelect do
  @moduledoc """
  A reusable select filter module, see `Backpex.Filters.Select`.
  """

  use Backpex.Filters.Select

  import Ecto.Query

  alias Backpex.Filters.Select
  alias Demo.Category
  alias Demo.Post
  alias Demo.Repo

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
