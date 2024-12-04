defmodule Demo.Repo.Migrations.DropShortLinksUniqueIndex do
  use Ecto.Migration

  def change do
    drop index(:short_links, [:short_key])
  end
end
