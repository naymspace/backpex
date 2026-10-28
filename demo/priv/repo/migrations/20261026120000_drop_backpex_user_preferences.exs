defmodule Demo.Repo.Migrations.DropBackpexUserPreferences do
  use Ecto.Migration

  # The table only served the tests of the Ecto preferences adapter, which run in the library now.
  def up do
    drop table(:backpex_user_preferences)
  end

  def down do
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
