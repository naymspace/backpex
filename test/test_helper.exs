Ecto.Adapters.Postgres.storage_up(BackpexTestApp.Repo.config())

{:ok, _, _} =
  Ecto.Migrator.with_repo(BackpexTestApp.Repo, fn repo ->
    Ecto.Migrator.run(repo, :up, all: true)
  end)


ExUnit.start()

Ecto.Adapters.SQL.Sandbox.mode(BackpexTestApp.Repo, :manual)
