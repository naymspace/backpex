alias Backpex.Test.Endpoint
alias Backpex.Test.OptionsPubSub
alias Backpex.Test.Repo
alias Ecto.Adapters.SQL.Sandbox

# Recreate the database of the test app, so changes to its migrations always apply. Each `MIX_TEST_PARTITION` has its
# own database.
repo_config = Repo.config()

if output = Application.get_env(:backpex, :test_db_port_error) do
  raise """
  The integration tests could not find the port of the `postgres` service with `docker compose port postgres 5432`:

  #{output}

  Start the database of the development environment with `docker compose up -d postgres`, set `DB_HOSTNAME` and
  `DB_PORT` to use another one, or run only the unit tests with `INTEGRATION_TESTS=false mix test`.
  """
end

case Ecto.Adapters.Postgres.storage_down(repo_config) do
  result when result in [:ok, {:error, :already_down}] ->
    :ok

  {:error, reason} when is_binary(reason) ->
    if reason =~ "is being accessed by other users" do
      raise """
      The database #{repo_config[:database]} of the integration tests is in use: #{reason}

      Stop the other test run or IEx session that uses it, or run the tests with another `MIX_TEST_PARTITION`.
      """
    else
      raise """
      The integration tests could not reach PostgreSQL at #{repo_config[:hostname]}:#{repo_config[:port]}: #{reason}

      Start the database of the development environment with `docker compose up -d postgres`, set `DB_HOSTNAME` and
      `DB_PORT` to use another one, or run only the unit tests with `INTEGRATION_TESTS=false mix test`.
      """
    end

  {:error, reason} ->
    raise "The integration tests could not drop the database #{repo_config[:database]}: #{inspect(reason)}"
end

:ok = Ecto.Adapters.Postgres.storage_up(repo_config)

File.rm_rf!(Backpex.Test.Uploads.dir())

{:ok, _apps} = Application.ensure_all_started([:ecto_sql, :ex_machina])

{:ok, _pid} =
  Supervisor.start_link(
    [
      Repo,
      {Phoenix.PubSub, name: Backpex.Test.AppPubSub},
      # The PubSub server of `Backpex.Test.PubSubNoteLive`, which configures its own.
      Supervisor.child_spec({Phoenix.PubSub, name: OptionsPubSub}, id: OptionsPubSub),
      Endpoint
    ],
    strategy: :one_for_one
  )

Ecto.Migrator.run(Repo, Path.join(repo_config[:priv], "migrations"), :up, all: true, log: false)
Sandbox.mode(Repo, :manual)

# The endpoint listens on a random port, see `config/test.exs`.
{:ok, {_ip, port}} = Endpoint.server_info(:http)
Application.put_env(:phoenix_test, :base_url, "http://localhost:#{port}")

# The browser tests are tagged `:e2e` and need Playwright (`bun install`) and the assets of `bun run e2e:assets`.
# They only run with `mix test --only e2e` or `--include e2e`.
if Enum.any?(ExUnit.configuration()[:include], &(&1 == :e2e or match?({:e2e, _value}, &1))) do
  {:ok, _pid} = PhoenixTest.Playwright.Supervisor.start_link()
end

ExUnit.configure(exclude: [e2e: true])
ExUnit.start()
