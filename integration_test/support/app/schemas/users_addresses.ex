defmodule Backpex.Test.UsersAddresses do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "users_addresses" do
    belongs_to :user, Backpex.Test.User, type: :id
    belongs_to :address, Backpex.Test.Address, type: :binary_id

    field :type, Ecto.Enum, values: [:shipping, :billing]

    timestamps()
  end

  @required_fields ~w[type address_id]a

  def changeset(user_address, attrs) do
    user_address
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
  end
end
