import Config

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  backpex: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.4.3",
  backpex: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason


# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :backpex, BackpexTestApp.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "backpex_test_app_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

config :backpex,
  ecto_repos: [BackpexTestApp.Repo],
  generators: [timestamp_type: :utc_datetime]

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :backpex, BackpexTestAppWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "oCZaLnzCj46Szf2wAhkb5SjQ7B9BGG5D43cP2lC+Fj87VALcSnzVrPR2hjI+jVeh",
  server: false

# Configures the endpoint
config :backpex, BackpexTestAppWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: BackpexTestAppWeb.ErrorHTML, json: BackpexTestAppWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: BackpexTestApp.PubSub,
  live_view: [signing_salt: "FK51iEv0"]

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

config :phoenix_test, :endpoint, BackpexTestAppWeb.Endpoint
