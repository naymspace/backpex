defmodule Demo.Repo.Migrations.ProductsAddMoreInfo do
  use Ecto.Migration

  def change do
    alter table(:products) do
      add :more_info, :map
    end
  end
end
