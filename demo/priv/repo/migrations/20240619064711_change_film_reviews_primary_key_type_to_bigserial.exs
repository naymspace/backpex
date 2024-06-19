defmodule Demo.Repo.Migrations.ChangeFilmReviewsPrimaryKeyTypeToBigserial do
  use Ecto.Migration

  def up do
    alter table(:film_reviews) do
      add :new_id, :bigserial
    end

    execute "UPDATE film_reviews SET new_id = nextval('film_reviews_new_id_seq')"

    execute "ALTER TABLE film_reviews DROP CONSTRAINT film_reviews_pkey"

    alter table(:film_reviews) do
      remove :id
    end

    rename table(:film_reviews), :new_id, to: :id

    execute "ALTER TABLE film_reviews ADD PRIMARY KEY (id)"
  end
end
