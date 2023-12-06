defmodule Demo.Repo.Migrations.AddUsersAddressesPrimary do
  use Ecto.Migration

  def change do
    alter table(:users_addresses) do
      add(:primary, :boolean, default: false, null: false)
    end
  end
end
