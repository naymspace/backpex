defmodule DemoWeb.Filters.PostUserSelect do
  @moduledoc """
  Implementation of the `Backpex.Filters.Select` behaviour.
  """

  use Backpex.Filters.Select

  alias Demo.Post
  alias Demo.Repo

  @impl Backpex.Filter
  def label, do: "Author"

  @impl Backpex.Filters.Select
  def prompt, do: "Select an option..."

  @impl Backpex.Filters.Select
  def options do
    query =
      from p in Post,
        join: u in assoc(p, :user),
        distinct: p.user_id,
        select: {u.username, u.id}

    Repo.all(query)
  end

  @impl Backpex.Filter
  def query(query, attribute, value) do
    where(query, [x], field(x, ^attribute) == ^value)
  end
end
