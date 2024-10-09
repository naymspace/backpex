defmodule Demo.Product do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  alias Demo.ShortLink
  alias Demo.Supplier

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "products" do
    field :name, :string
    field :quantity, :integer
    field :manufacturer, :string
    field :images, {:array, :string}

    field :price, Backpex.Ecto.Amount.Type,
      currency: :EUR,
      opts: [separator: ".", delimiter: ",", symbol_on_right: true, symbol_space: true]

    has_many :suppliers, Supplier, on_replace: :delete, on_delete: :delete_all
    has_many :short_links, ShortLink, on_replace: :delete, on_delete: :delete_all, foreign_key: :product_id

    timestamps()
  end

  @required_fields ~w[name quantity manufacturer price]a
  @optional_fields ~w[images]a

  def changeset(product, attrs, _metadata \\ []) do
    product
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> cast_assoc(:suppliers,
      with: &Demo.Supplier.changeset/2,
      sort_param: :suppliers_order,
      drop_param: :suppliers_delete
    )
    |> cast_assoc(:short_links,
      with: &Demo.ShortLink.changeset/2,
      sort_param: :short_links_order,
      drop_param: :short_links_delete
    )
    |> validate_required(@required_fields)
    |> validate_length(:images, max: 2)
  end
end
