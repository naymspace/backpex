defmodule Demo.Repo.Migrations.AddSecondCategoryToPost do
  use Ecto.Migration

  def change do
    alter table(:posts) do
      add(:second_category_id, references(:categories))
    end
  end
end
