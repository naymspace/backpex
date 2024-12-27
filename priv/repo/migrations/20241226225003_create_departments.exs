defmodule BackpexTestApp.Repo.Migrations.CreateDepartments do
  use Ecto.Migration

  def change do
    create table(:departments) do
      add :name, :string

      timestamps(type: :utc_datetime)
    end
  end
end
