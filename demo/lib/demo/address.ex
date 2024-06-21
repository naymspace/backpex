defmodule Demo.Address do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "addresses" do
    field :street, :string
    field :zip, :string
    field :city, :string
    field :country, Ecto.Enum, values: [:de, :at, :ch]
    field :full_address, :string, virtual: true

    timestamps()
  end

  @required_fields ~w[street zip city country]a

  @doc false
  def changeset(address, attrs, _metadata \\ []) do
    address
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
  end

  def update_changeset(address, attrs, _metadata \\ []) do
    address
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
  end

  def create_changeset(address, attrs, _metadata \\ []) do
    address
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
  end
end
