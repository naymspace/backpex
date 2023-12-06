defmodule Demo.Repo.Migrations.CreateTagsTable do
  use Ecto.Migration

  def change do
    create table(:tags) do
      add(:name, :string, null: false)

      timestamps()
    end

    create table(:posts_tags) do
      add(:post_id, references(:posts), null: false)
      add(:tag_id, references(:tags), null: false)

      timestamps()
    end
  end
end
