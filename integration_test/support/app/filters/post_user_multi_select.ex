defmodule Backpex.Test.Filters.PostUserMultiSelect do
  @moduledoc "A multi select filter with the authors of the posts as options."

  use Backpex.Filters.MultiSelect

  alias Backpex.Filters.Select
  alias Backpex.Test.Post
  alias Backpex.Test.Repo

  @impl Backpex.Filter
  def label, do: "Users"

  @impl Select
  def prompt, do: "Select users ..."

  @impl Select
  def options(_assigns) do
    query =
      from p in Post,
        join: u in assoc(p, :user),
        distinct: p.user_id,
        select: {fragment("? || ' ' || ?", u.first_name, u.last_name), u.id}

    Repo.all(query)
  end
end
