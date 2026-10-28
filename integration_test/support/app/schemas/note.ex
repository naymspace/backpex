defmodule Backpex.Test.Note do
  @moduledoc "A minimal record with an integer primary key, used by `Backpex.Test.NoteLive`."
  use Ecto.Schema

  import Ecto.Changeset

  schema "notes" do
    field :title, :string
    timestamps()
  end

  def changeset(note, attrs, _metadata \\ []) do
    note
    |> cast(attrs, [:title])
    |> validate_required([:title])
  end
end
