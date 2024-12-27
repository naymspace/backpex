defmodule BackpexTestApp.Repo.Migrations.CreateFunctions do
  use Ecto.Migration

  def change do
    create table(:functions) do
      add :name, :string

      timestamps(type: :utc_datetime)
    end
  end
end
