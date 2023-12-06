defmodule Demo.Newsletter.Contact do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  schema "contact" do
    field :email, :string
  end

  @required_fields ~w[email]a

  def changeset(change, attrs) do
    change
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
  end
end
