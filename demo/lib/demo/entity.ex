defmodule Demo.Entity do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "entities" do
    field :identity, :string
    field :type, :string
    field :fields, :map, default: %{}

    timestamps()
  end

  @required_fields [:identity, :type, :fields]
  @doc false
  def changeset(address, attrs, _metadata \\ []) do
    address
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
  end
end
