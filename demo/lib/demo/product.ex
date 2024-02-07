defmodule Demo.Product do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  alias Demo.Supplier

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "products" do
    field(:name, :string)
    field(:quantity, :integer)
    field(:manufacturer, :string)

    field(:price, Backpex.Ecto.Amount.Type,
      currency: :EUR,
      opts: [separator: ".", delimiter: ",", symbol_on_right: true, symbol_space: true]
    )

    has_many(:suppliers, Supplier, on_replace: :delete, on_delete: :delete_all)

    timestamps()
  end

  @required_fields ~w[name quantity manufacturer price]a
  @optional_fields ~w[]a

  def changeset(product, attrs, _metadata \\ []) do
    product
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> cast_assoc(:suppliers,
      with: &Demo.Supplier.changeset/2,
      sort_param: :suppliers_order,
      drop_param: :suppliers_delete
    )
    |> validate_required(@required_fields)
  end
end
