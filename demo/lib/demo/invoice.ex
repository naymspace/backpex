defmodule Demo.Invoice do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "invoices" do
    field(:company, :string)

    field(:amount, Backpex.Ecto.Amount.Type,
      currency: :EUR,
      opts: [separator: ".", delimiter: ",", symbol_on_right: true, symbol_space: true]
    )

    timestamps()
  end

  @required_fields ~w[company amount]a
  @optional_fields ~w[]a

  def update_changeset(invoice, attrs) do
    invoice
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end

  def create_changeset(invoice, attrs) do
    invoice
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end
