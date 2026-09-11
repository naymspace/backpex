defmodule Demo.Supplier do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  alias Demo.Product

  @primary_key {:id, :binary_id, autogenerate: true}

  @countries ["Austria", "France", "Germany", "Italy", "Spain", "Switzerland"]

  def countries, do: @countries

  schema "suppliers" do
    field :name, :string
    field :url, :string
    field :country, Ecto.Enum, values: Enum.map(@countries, &String.to_atom/1)
    field :contract_date, :date
    field :minimum_order, Money.Ecto.Amount.Type
    field :preferred, :boolean, default: false

    belongs_to :product, Product, type: :binary_id

    timestamps()
  end

  @required_fields ~w[name url]a
  @optional_fields ~w[country contract_date minimum_order preferred]a

  def changeset(supplier, attrs) do
    supplier
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end
