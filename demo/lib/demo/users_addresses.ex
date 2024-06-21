defmodule Demo.UsersAddresses do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Demo.Address
  alias Demo.User

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "users_addresses" do
    belongs_to(:user, User, type: :id)
    belongs_to(:address, Address, type: :binary_id)
    field(:type, Ecto.Enum, values: [:shipping, :billing])
    field(:primary, :boolean, default: false)

    timestamps()
  end

  @required_fields ~w[type primary address_id]a

  @doc false
  def changeset(user_address, attrs) do
    user_address
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:address_id)
  end
end
