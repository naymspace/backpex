defmodule Backpex.Test.Sample do
  @moduledoc """
  A record with one column for every scalar field type of Backpex, used by `Backpex.Test.SampleLive`.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @fields ~w[text textarea number boolean select multi_select checkgroup date date_time time email url currency upload category_id]a

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "samples" do
    field :text, :string
    field :textarea, :string
    field :number, :integer
    field :boolean, :boolean, default: false
    field :select, Ecto.Enum, values: [:one, :two, :three]
    field :multi_select, {:array, :string}, default: []
    field :checkgroup, {:array, :string}, default: []
    field :date, :date
    field :date_time, :utc_datetime
    field :time, :time
    field :email, :string
    field :url, :string
    field :currency, Money.Ecto.Amount.Type
    field :upload, :string
    belongs_to :category, Backpex.Test.Category, type: :binary_id
    timestamps()
  end

  def changeset(sample, attrs, _metadata \\ []) do
    sample
    |> cast(attrs, @fields)
    |> validate_required([:text])
  end
end
