defmodule Demo.Repo.Migrations.CreateSuppliers do
  use Ecto.Migration

  def change do
    create table(:suppliers) do
      add(:name, :string, null: false)
      add(:url, :string, null: false)
      add(:product_id, references(:products, on_delete: :delete_all), null: false)

      timestamps()
    end
  end
end
