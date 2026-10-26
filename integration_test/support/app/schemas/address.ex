defmodule Backpex.Test.Address do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "addresses" do
    field :street, :string
    field :zip, :string
    field :city, :string
    field :country, Ecto.Enum, values: [:de, :at, :ch, :us, :ca]

    timestamps()
  end

  @required_fields ~w[street zip city country]a

  def changeset(address, attrs, _metadata \\ []) do
    address
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
  end
end
