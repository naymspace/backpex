defmodule Demo.Repo.Migrations.CreateShortLinks do
  use Ecto.Migration

  def change do
    create table(:short_links, primary_key: false) do
      add :short_key, :string, primary_key: true
      add :url, :string

      add(:product_id, references(:products, type: :binary_id))

      timestamps()
    end
  end
end
