defmodule Demo.Repo.Migrations.CreateInvoices do
  use Ecto.Migration

  def change do
    create table(:invoices) do
      add(:company, :string, null: false)
      add(:amount, :bigint, null: false)

      timestamps()
    end
  end
end
