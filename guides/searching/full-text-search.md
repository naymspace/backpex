# Full-Text Search

Backpex allows you to perform full-text searches on resources. It uses the built-in [PostgreSQL full-text search functionality](https://www.postgresql.org/docs/current/textsearch.html).

## Create a Generated Column

Backpex forces you to create a generated column to use the full-text search functionality. It must contain a tsvector that is generated from all the columns that you want to be considered when searching. You are free to choose a name for this column.

Below is an example of a generated column for a movie review resource with a title column and an overview column. Both columns should be searchable.

```elixir
# in the database up migration

execute("""
ALTER TABLE film_reviews
  ADD COLUMN generated_tsvector tsvector
  GENERATED ALWAYS AS (
    to_tsvector('english', coalesce(title, '') || ' ' || coalesce(overview, ''))
  ) STORED;
""")
```

You can also concat multiple tsvectors in the generated column. This is useful if the table contains data in different languages. We recommend that you specify the language when using the `to_tsvector` function. Otherwise the default language will be used.

## Create an Index

To increase the speed of full-text searches, especially for resources with large amounts of data, you should create an index on the generated column created in the previous step.

We strongly recommend that you use a GIN index, as it makes full-text searches really fast. The disadvantage is that a GIN index takes up a lot of disk space, so if you are limited in disk space, feel free to use a GiST index instead.

```elixir
# in the database up migration

execute("""
CREATE INDEX film_reviews_search_idx ON film_reviews USING GIN(generated_tsvector);
""")
```

```elixir
# in the database down migration

execute("""
DROP INDEX film_reviews_search_idx;
""")

drop table(:film_reviews)
```

> #### Important {: .info}
>
> Note that you must explicitly define up and down migrations. Otherwise, the index cannot be dropped.

To enable full-text search, you need to specify the name of the generated column in the live resource of the corresponding resource:

```elixir
# in the live resource

use Backpex.LiveResource,
  full_text_search: :generated_tsvector
```

You can now perform full-text searches on the resource index view.