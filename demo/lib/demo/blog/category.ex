defmodule Demo.Blog.Category do
  @moduledoc false

  use Ash.Resource,
    domain: Demo.Blog,
    data_layer: AshPostgres.DataLayer

  postgres do
    repo Demo.RepoAsh
    table "categories"
  end

  actions do
    defaults [:read]
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string
  end

  # TODO: validations
end
