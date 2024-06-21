defmodule Demo.Repo.Migrations.CreateFilmReviews do
  use Ecto.Migration

  def up do
    create table(:film_reviews) do
      add :title, :string, null: false
      add :overview, :text, null: false
    end

    execute("""
    ALTER TABLE film_reviews
      ADD COLUMN generated_tsvector tsvector
      GENERATED ALWAYS AS (
        to_tsvector('english', coalesce(title, '') || ' ' || coalesce(overview, ''))
      ) STORED;
    """)

    execute("""
    CREATE INDEX film_reviews_search_idx ON film_reviews USING GIN (generated_tsvector);
    """)
  end

  def down do
    execute("""
    DROP INDEX IF EXISTS film_reviews_search_idx;
    """)

    drop table(:film_reviews)
  end
end
