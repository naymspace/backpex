defmodule Demo.ShortLink do
  @moduledoc """
  Example for handling primary keys that are not called "id".
  """
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query, warn: false

  alias Demo.Repo

  @primary_key false
  schema "short_links" do
    field :short_key, :string, primary_key: true
    field :url, :string

    belongs_to :product, Demo.Product, type: :binary_id

    timestamps()
  end

  @required_fields ~w[short_key url]a
  @optional_fields ~w[product_id]a

  def changeset(short_link, attrs, _metadata \\ []) do
    short_link
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> cast_assoc(:product, with: &Demo.Product.changeset/2)
    |> add_short_key()
    |> validate_required(@required_fields)
    |> validate_format(:short_key, ~r/^[A-Za-z0-9_-]+$/,
      message: "must be URL safe (only letters, numbers, underscores, and hyphens)"
    )
    |> validate_length(:short_key, min: 1, max: 64)
    |> unique_constraint(:short_key)
  end

  defp add_short_key(changeset) do
    case get_field(changeset, :short_key) do
      nil -> put_change(changeset, :short_key, generate_short_key())
      _ -> changeset
    end
  end

  def generate_unique_short_key do
    key = generate_short_key()
    if key_exists?(key), do: generate_unique_short_key(), else: key
  end

  def generate_short_key(length \\ 8) do
    length
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
    |> binary_part(0, length)
  end

  defp key_exists?(key), do: Repo.exists?(from s in __MODULE__, where: s.short_key == ^key)
end
