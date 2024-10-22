defmodule Demo.Category do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "categories" do
    field :name, :string

    timestamps()
  end

  @required_fields ~w[name]a
  @optional_fields ~w[]a

  def update_changeset(category, attrs, _metadata \\ []) do
    category
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end

  def create_changeset(category, attrs, _metadata \\ []) do
    category
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end
