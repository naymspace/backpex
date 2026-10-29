defmodule Backpex.Test.ShortLink do
  @moduledoc """
  A record whose primary key is the string `short_key` instead of an `id`.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false
  schema "short_links" do
    field :short_key, :string, primary_key: true
    field :url, :string

    belongs_to :product, Backpex.Test.Product, type: :binary_id

    timestamps()
  end

  @required_fields ~w[short_key url]a

  def changeset(short_link, attrs, _metadata \\ []) do
    short_link
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
  end
end
