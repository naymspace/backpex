defmodule Demo.Repo.Migrations.AddExtraSuppliersFields do
  use Ecto.Migration

  def change do
    alter table(:suppliers) do
      add :country, :string, null: true
      add :contract_date, :date, null: true
      add :minimum_order, :integer, default: 0, null: false
      add :preferred, :boolean, null: true
    end
  end
end
