defmodule Backpex.Test.Repo.Migrations.CreateTables do
  use Ecto.Migration

  # The repo is configured with `migration_primary_key: [type: :binary_id]`, so every table without an explicit primary
  # key gets a UUID `id`. `users` and `notes` have an integer id and `short_links` a string primary key.
  def change do
    create table(:users, primary_key: false) do
      add(:id, :bigserial, primary_key: true)
      add(:username, :string, null: false)
      add(:first_name, :string, null: false)
      add(:last_name, :string, null: false)
      add(:age, :integer)
      add(:role, :string, null: false)
      add(:avatar, :string)
      add(:social_links, :map)
      add(:web_links, :map)
      add(:permissions, {:array, :string}, default: [], null: false)
      add(:deleted_at, :utc_datetime)
      timestamps()
    end

    create table(:addresses) do
      add(:street, :string, null: false)
      add(:zip, :string, null: false)
      add(:city, :string, null: false)
      add(:country, :string, null: false)
      timestamps()
    end

    create table(:users_addresses) do
      add(:user_id, references(:users, type: :bigserial), null: false)
      add(:address_id, references(:addresses), null: false)
      add(:type, :string, null: false)
      add(:primary, :boolean, default: false, null: false)
      timestamps()
    end

    create table(:categories) do
      add(:name, :string, null: false)
      timestamps()
    end

    create table(:posts) do
      add(:title, :string, null: false)
      add(:body, :text, null: false)
      add(:published, :boolean, default: false, null: false)
      add(:likes, :integer, default: 0, null: false)
      add(:category_id, references(:categories))
      add(:user_id, references(:users, type: :bigserial))
      timestamps()
    end

    create table(:tags) do
      add(:name, :string, null: false)
      timestamps()
    end

    create table(:posts_tags) do
      add(:post_id, references(:posts), null: false)
      add(:tag_id, references(:tags), null: false)
      timestamps()
    end

    create table(:products) do
      add(:name, :string, null: false)
      add(:price, :bigint, null: false)
      add(:quantity, :integer, default: 0, null: false)
      add(:manufacturer, :string, null: false)
      add(:images, {:array, :string})
      timestamps()
    end

    create table(:suppliers) do
      add(:name, :string, null: false)
      add(:url, :string, null: false)
      add(:country, :string)
      add(:contract_date, :date)
      add(:minimum_order, :integer, default: 0, null: false)
      add(:preferred, :boolean)
      add(:product_id, references(:products, on_delete: :delete_all), null: false)
      timestamps()
    end

    create table(:short_links, primary_key: false) do
      add(:short_key, :string, primary_key: true)
      add(:url, :string, null: false)
      add(:product_id, references(:products))
      timestamps()
    end

    create table(:invoices) do
      add(:company, :string, null: false)
      add(:amount, :bigint, null: false)
      timestamps()
    end

    create table(:film_reviews) do
      add(:title, :string, null: false)
      add(:overview, :text, null: false)
    end

    execute(
      """
      ALTER TABLE film_reviews ADD COLUMN generated_tsvector tsvector
        GENERATED ALWAYS AS (to_tsvector('english', coalesce(title, '') || ' ' || coalesce(overview, ''))) STORED
      """,
      "ALTER TABLE film_reviews DROP COLUMN generated_tsvector"
    )

    create table(:backpex_user_preferences) do
      add(:user_id, :integer, null: false)
      add(:tenant_id, :integer, null: false)
      add(:key, :string, null: false)
      add(:value, :map, null: false, default: %{})
      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:backpex_user_preferences, [:user_id, :tenant_id, :key]))

    create table(:notes, primary_key: false) do
      add(:id, :bigserial, primary_key: true)
      add(:title, :string, null: false)
      timestamps()
    end

    create table(:samples) do
      add(:text, :string, null: false)
      add(:textarea, :text)
      add(:number, :integer)
      add(:boolean, :boolean, default: false, null: false)
      add(:select, :string)
      add(:multi_select, {:array, :string}, default: [], null: false)
      add(:checkgroup, {:array, :string}, default: [], null: false)
      add(:date, :date)
      add(:date_time, :utc_datetime)
      add(:time, :time)
      add(:email, :string)
      add(:url, :string)
      add(:currency, :bigint)
      add(:upload, :string)
      add(:category_id, references(:categories))
      timestamps()
    end
  end
end
