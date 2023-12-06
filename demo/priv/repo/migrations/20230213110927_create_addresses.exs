defmodule Demo.Repo.Migrations.CreateAddresses do
  use Ecto.Migration

  def change do
    create table(:addresses) do
      add(:street, :string, null: false)
      add(:zip, :string, null: false)
      add(:city, :string, null: false)
      add(:country, :string, null: false)

      timestamps()
    end
  end
end
