defmodule Demo.Repo.Migrations.CreateUsersAddresses do
  use Ecto.Migration

  def change do
    create table(:users_addresses) do
      add :user_id, references(:users, type: :bigserial), null: false
      add :address_id, references(:addresses), null: false
      add :type, :string, null: false
      add :primary, :boolean, default: false, null: false

      timestamps()
    end
  end
end
