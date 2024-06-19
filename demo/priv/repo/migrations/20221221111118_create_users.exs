defmodule Demo.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users) do
      add(:username, :string, null: false)
      add(:first_name, :string, null: false)
      add(:last_name, :string, null: false)
      add(:role, :string, null: false)
      add(:avatar, :string, null: true)

      timestamps()
    end
  end
end
