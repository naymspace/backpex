import Config

config :logger, :default_handler, false
config :logger, :level, :debug

config :backpex,
  ecto_repos: [Backpex.Test.Repo],
  pubsub_server: Backpex.Test.AppPubSub,
  translator_function: {Backpex.Test.Translator, :translate},
  error_translator_function: {Backpex.Test.Translator, :translate}

# The library tests run against a real PostgreSQL database. Locally they use the `postgres` service of `compose.yml`,
# whose host port is random unless it is set in `.env`, so the port is looked up with `docker compose` if `DB_PORT` is
# unset.
db_port =
  System.get_env("DB_PORT") ||
    with docker when is_binary(docker) <- System.find_executable("docker"),
         {output, 0} <- System.cmd(docker, ~w(compose port postgres 5432), stderr_to_stdout: true) do
      output |> String.trim() |> String.split(":") |> List.last()
    else
      _error -> "5432"
    end

config :backpex, Backpex.Test.Repo,
  hostname: System.get_env("DB_HOSTNAME", "localhost"),
  port: String.to_integer(db_port),
  username: System.get_env("DB_USERNAME", "postgres"),
  password: System.get_env("DB_PASSWORD", "postgres"),
  database: "backpex_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2,
  priv: "test/support/app/priv",
  migration_primary_key: [name: :id, type: :binary_id],
  log: false

# Port 0 lets the OS pick a free port, so several checkouts can run their tests at the same time. `test_helper.exs` hands
# the actual port to `phoenix_test`.
config :backpex, Backpex.Test.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  http: [ip: {127, 0, 0, 1}, port: 0],
  url: [host: "localhost"],
  server: true,
  secret_key_base: String.duplicate("backpex_test_secret_", 4),
  live_view: [signing_salt: "backpex_test_salt"],
  pubsub_server: Backpex.Test.AppPubSub,
  render_errors: [formats: [html: Backpex.Test.ErrorHTML], layout: false]

config :phoenix, :plug_init_mode, :runtime

config :phoenix_test,
  endpoint: Backpex.Test.Endpoint,
  otp_app: :backpex,
  playwright: [
    assets_dir: "./",
    browser: :chromium,
    browser_launch_timeout: 10_000,
    trace: System.get_env("PW_TRACE", "false") in ~w(t true),
    trace_dir: "tmp/e2e/traces"
  ]

config :money,
  default_currency: :USD,
  separator: ",",
  delimiter: ".",
  symbol_on_right: false,
  symbol_space: false
