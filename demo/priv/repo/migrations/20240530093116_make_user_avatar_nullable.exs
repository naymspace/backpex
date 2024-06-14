defmodule Demo.Repo.Migrations.MakeUserAvatarNullable do
  use Ecto.Migration

  def change do
    alter table(:users) do
      modify(:avatar, :string, null: true)
    end
  end
end
