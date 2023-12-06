defmodule Demo.Repo.Migrations.AddUserWebLinks do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add(:web_links, :map)
    end
  end
end
