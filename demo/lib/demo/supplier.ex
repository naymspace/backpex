defmodule Demo.Supplier do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "suppliers" do
    field :name, :string
    field :url, :string
    belongs_to :product, Demo.Product, type: :binary_id

    timestamps()
  end

  @required_fields ~w[name url]a

  def changeset(supplier, attrs) do
    supplier
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
  end
end
