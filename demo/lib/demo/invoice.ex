defmodule Demo.Invoice do
  @moduledoc false

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "invoices" do
    field :company, :string

    field :amount, Money.Ecto.Amount.Type

    timestamps()
  end
end
