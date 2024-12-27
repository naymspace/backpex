defmodule BackpexTestApp.Payroll.Function do
  use Ecto.Schema
  import Ecto.Changeset

  schema "functions" do
    field :name, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(functions, attrs) do
    functions
    |> cast(attrs, [:name])
    |> validate_required([:name])
  end

  def update_changeset(function, attrs, _opts) do
    changeset(function, attrs)
  end

  def create_changeset(function, attrs, _opts) do
    changeset(function, attrs)
  end
end
