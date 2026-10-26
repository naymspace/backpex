alias Backpex.Test.Endpoint
alias Backpex.Test.Repo
alias Ecto.Adapters.SQL.Sandbox

# Recreate the database of the test app, so changes to its migrations always apply. Each `MIX_TEST_PARTITION` has its
# own database.
repo_config = Repo.config()
Ecto.Adapters.Postgres.storage_down(repo_config)
:ok = Ecto.Adapters.Postgres.storage_up(repo_config)

{:ok, _apps} = Application.ensure_all_started([:ecto_sql, :ex_machina])

{:ok, _pid} =
  Supervisor.start_link(
    [
      Repo,
      {Phoenix.PubSub, name: Backpex.Test.AppPubSub},
      Endpoint
    ],
    strategy: :one_for_one
  )

Ecto.Migrator.run(Repo, Path.join(repo_config[:priv], "migrations"), :up, all: true, log: false)
Sandbox.mode(Repo, :manual)

# The endpoint listens on a random port, see `config/test.exs`.
{:ok, {_ip, port}} = Endpoint.server_info(:http)
Application.put_env(:phoenix_test, :base_url, "http://localhost:#{port}")

# The browser tests are tagged `:e2e` and need Playwright (`bun install`) and the assets of `bun run e2e:assets`. They only
# run with `mix test --only e2e` or `--include e2e`.
if Enum.any?(ExUnit.configuration()[:include], &(&1 == :e2e or match?({:e2e, _value}, &1))) do
  {:ok, _pid} = PhoenixTest.Playwright.Supervisor.start_link()
end

ExUnit.configure(exclude: [e2e: true])
ExUnit.start()
