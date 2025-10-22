defmodule Demo.Repo.Migrations.CreateEntities do
  use Ecto.Migration

  def change do
    create table(:entities) do
      add :identity, :string, null: false
      add :type, :string, null: false
      add :fields, :map
      timestamps()
    end
  end
end
