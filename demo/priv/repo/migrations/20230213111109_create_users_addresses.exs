defmodule Demo.Repo.Migrations.CreateUsersAddresseses do
  use Ecto.Migration

  def change do
    create table(:users_addresses) do
      add(:user_id, references(:users), null: false)
      add(:address_id, references(:addresses), null: false)
      add(:type, :string, null: false)

      timestamps()
    end
  end
end
