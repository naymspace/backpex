defmodule Demo.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false) do
      add :id, :bigserial, primary_key: true
      add :username, :string, null: false
      add :first_name, :string, null: false
      add :last_name, :string, null: false
      add :age, :integer, null: true
      add :role, :string, null: false
      add :avatar, :string, null: true
      add :social_links, :map, null: true
      add :web_links, :map, null: true
      add :permissions, {:array, :string}, null: true
      add :deleted_at, :utc_datetime, null: true

      timestamps()
    end
  end
end
