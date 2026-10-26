defmodule Backpex.Test.Post do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "posts" do
    field :title, :string
    field :body, :string
    field :published, :boolean, default: false
    field :likes, :integer, default: 0

    belongs_to :user, Backpex.Test.User, type: :id
    belongs_to :category, Backpex.Test.Category, type: :binary_id

    many_to_many :tags, Backpex.Test.Tag, join_through: Backpex.Test.PostsTags, on_replace: :delete

    timestamps()
  end

  @required_fields ~w[title body published]a
  @optional_fields ~w[user_id category_id likes]a

  def update_changeset(post, attrs, _metadata \\ []), do: changeset(post, attrs)

  def create_changeset(post, attrs, _metadata \\ []), do: changeset(post, attrs)

  defp changeset(post, attrs) do
    post
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end
