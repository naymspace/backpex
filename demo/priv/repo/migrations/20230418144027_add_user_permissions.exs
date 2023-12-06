defmodule Demo.Repo.Migrations.AddUserPermissions do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add(:permissions, {:array, :string})
    end
  end
end
