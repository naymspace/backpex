defmodule Demo.Repo.Migrations.AddEmergencyContactToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :emergency_contact, :map, null: true
    end
  end
end
