defmodule Backpex.Test.Tag do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "tags" do
    field :name, :string

    many_to_many :posts, Backpex.Test.Post, join_through: Backpex.Test.PostsTags, on_replace: :delete

    timestamps()
  end

  def changeset(tag, attrs, _metadata \\ []) do
    tag
    |> cast(attrs, [:name])
    |> validate_required([:name])
  end
end
