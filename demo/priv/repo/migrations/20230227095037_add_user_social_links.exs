defmodule Demo.Repo.Migrations.AddUserSocialLinks do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add(:social_links, :map)
    end
  end
end
