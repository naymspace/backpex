defmodule Demo.ShortLink do
  @moduledoc """
  Example for handling primary keys that are not called "id".
  """
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false
  schema "short_links" do
    field :short_key, :string, primary_key: true
    field :url, :string

    belongs_to :product, Demo.Product, type: :binary_id

    timestamps()
  end

  @required_fields ~w[short_key url product_id]a

  def changeset(short_link, attrs, metadata \\ []) do
    short_link
    |> cast(attrs, @required_fields)
    |> cast_assoc(:product, with: &Product.changeset/2)
    |> add_short_key()
    |> validate_required(@required_fields)
  end

  defp add_short_key(changeset) do
    case get_field(changeset, :short_key) do
      nil -> put_change(changeset, :short_key, generate_short_key())
      _ -> changeset
    end
  end

  def generate_short_key do
    :crypto.strong_rand_bytes(8)
    |> Base.encode64()
    |> String.replace("+", "-")
    |> String.replace("/", "_")
    |> String.replace("=", "")
  end
end
