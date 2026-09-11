defmodule Demo.Repo.Migrations.CreateBackpexUserPreferences do
  use Ecto.Migration

  def change do
    create table(:backpex_user_preferences) do
      add(:user_id, :integer, null: false)
      add(:tenant_id, :integer, null: false)
      add(:key, :string, null: false)
      add(:value, :map, null: false, default: %{})
      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:backpex_user_preferences, [:user_id, :tenant_id, :key]))
  end
end
