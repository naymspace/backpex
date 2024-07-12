defmodule Demo.PostsTags do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Demo.Post
  alias Demo.Tag

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "posts_tags" do
    belongs_to :post, Post, type: :binary_id
    belongs_to :tag, Tag, type: :binary_id

    timestamps()
  end

  @required_fields ~w[post_id tag_id]a

  @doc false
  def changeset(post_tag, attrs) do
    post_tag
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:post_id)
    |> foreign_key_constraint(:tag_id)
  end
end
