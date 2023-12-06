defmodule Demo.Repo.Migrations.CreatePosts do
  use Ecto.Migration

  def change do
    create table(:posts) do
      add(:title, :string, null: false)
      add(:body, :text, null: false)
      add(:published, :boolean, default: false, null: false)
      add(:likes, :integer, default: 0, null: false)

      add(:category_id, references(:categories))
      add(:user_id, references(:users))

      timestamps()
    end
  end
end
