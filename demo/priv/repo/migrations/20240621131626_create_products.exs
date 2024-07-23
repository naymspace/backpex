defmodule Demo.Repo.Migrations.CreateProducts do
  use Ecto.Migration

  def change do
    create table(:products) do
      add :name, :string, null: false
      add :price, :bigint, null: false
      add :quantity, :integer, default: 0, null: false
      add :manufacturer, :string, null: false
      add :images, {:array, :string}, null: true

      timestamps()
    end
  end
end
