defmodule Demo.FilmReview do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "film_reviews" do
    field(:title, :string)
    field(:overview, :string)
  end

  @required_fields ~w[title overview]a

  def update_changeset(film_review, attrs, _metadata \\ []) do
    film_review
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
  end

  def create_changeset(film_review, attrs, _metadata \\ []) do
    film_review
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
  end
end
