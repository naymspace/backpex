defmodule Demo.Invoice do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "invoices" do
    field :company, :string

    field :amount, Backpex.Ecto.Amount.Type,
      currency: :EUR,
      opts: [separator: ".", delimiter: ",", symbol_on_right: true, symbol_space: true]

    timestamps()
  end
end
