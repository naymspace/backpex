defmodule Demo.Invoice do
  @moduledoc false

  use Ecto.Schema

  alias Money.Ecto.Amount.Type

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "invoices" do
    field :company, :string

    field :amount, Type

    timestamps()
  end
end
