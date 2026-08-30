defmodule Demo.Repo.Migrations.SetDefaultForPermissions do
  use Ecto.Migration

  def up do
    # Set default for new records
    execute "ALTER TABLE users ALTER COLUMN permissions SET DEFAULT '{}'::text[]"

    # Update existing NULL values to empty array
    execute "UPDATE users SET permissions = '{}' WHERE permissions IS NULL"
  end

  def down do
    execute "ALTER TABLE users ALTER COLUMN permissions DROP DEFAULT"
  end
end
