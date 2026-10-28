defmodule Backpex.Test.Category do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "categories" do
    field :name, :string

    timestamps()
  end

  def changeset(category, attrs, _metadata \\ []) do
    category
    |> cast(attrs, [:name])
    |> validate_required([:name])
  end
end
