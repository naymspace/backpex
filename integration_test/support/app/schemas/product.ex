defmodule Backpex.Test.Product do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  alias Backpex.Test.ShortLink

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "products" do
    field :name, :string
    field :quantity, :integer
    field :manufacturer, :string
    field :images, {:array, :string}

    field :price, Money.Ecto.Amount.Type

    has_many :short_links, ShortLink, on_replace: :delete, on_delete: :delete_all

    timestamps()
  end

  @required_fields ~w[name quantity manufacturer price]a
  @optional_fields ~w[images]a

  def changeset(product, attrs, _metadata \\ []) do
    product
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> cast_assoc(:short_links,
      with: &ShortLink.changeset/2,
      sort_param: :short_links_order,
      drop_param: :short_links_delete
    )
    |> validate_required(@required_fields)
  end
end
