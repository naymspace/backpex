defmodule DemoWeb.Filters.PostUserMultiSelect do
  @moduledoc """
  Implementation of the `Backpex.Filters.MultiSelect` behaviour.
  """

  use Backpex.Filters.MultiSelect

  alias Backpex.Filters.Select
  alias Demo.Post
  alias Demo.Repo

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
