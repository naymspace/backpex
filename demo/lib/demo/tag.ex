defmodule Demo.Tag do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "tags" do
    field :name, :string

    many_to_many(:posts, Demo.Post, join_through: Demo.PostsTags, on_replace: :delete)

    timestamps()
  end

  @required_fields ~w[name]a

  def update_changeset(category, attrs, _metadata \\ []) do
    category
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
  end

  def create_changeset(category, attrs, _metadata \\ []) do
    category
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
  end
end
