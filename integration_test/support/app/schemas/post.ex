defmodule Backpex.Test.Post do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "posts" do
    field :title, :string
    field :body, :string
    field :published, :boolean, default: false
    field :show_likes, :boolean, virtual: true
    field :likes, :integer, default: 0

    belongs_to :user, Backpex.Test.User, type: :id
    belongs_to :category, Backpex.Test.Category, type: :binary_id

    many_to_many :tags, Backpex.Test.Tag, join_through: Backpex.Test.PostsTags, on_replace: :delete

    timestamps()
  end

  @required_fields ~w[title body published]a
  @optional_fields ~w[show_likes user_id category_id likes]a

  def update_changeset(post, attrs, _metadata \\ []) do
    post
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> maybe_remove_likes()
  end

  def create_changeset(post, attrs, _metadata \\ []) do
    post
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> maybe_remove_likes()
  end

  defp maybe_remove_likes(post) do
    if get_change(post, :show_likes) do
      change(post, likes: 0)
    else
      post
    end
  end
end
