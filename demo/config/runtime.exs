import Config
import String, only: [to_integer: 1, to_atom: 1, to_existing_atom: 1]
import System, only: [get_env: 1, get_env: 2, fetch_env!: 1]

secret = fn name, bytes ->
  if config_env() == :test, do: bytes |> :crypto.strong_rand_bytes() |> Base.encode64(), else: fetch_env!(name)
end

config :demo, Demo.Repo,
  hostname: get_env("DB_HOSTNAME", "postgres"),
  username: get_env("DB_USERNAME", "postgres"),
  password: get_env("DB_PASSWORD", "postgres"),
  database: get_env("DB_DATABASE", "postgres"),
  port: get_env("DB_PORT", "5432") |> to_integer(),
  pool_size: get_env("DB_POOL_SIZE", "5") |> to_integer()

# The LiveDashboard is open in dev and test unless DASHBOARD_AUTH_ENABLED is "true". In prod it always requires
# the basic auth credentials from DASHBOARD_AUTH_USERNAME and DASHBOARD_AUTH_PASSWORD; while one of them is
# missing, DemoWeb.DashboardAuthPlug answers every request to the dashboard with 404.
config :demo, DemoWeb.DashboardAuthPlug,
  required: config_env() == :prod or get_env("DASHBOARD_AUTH_ENABLED") == "true",
  username: get_env("DASHBOARD_AUTH_USERNAME"),
  password: get_env("DASHBOARD_AUTH_PASSWORD")

config :demo, DemoWeb.Endpoint,
  http: [
    port: get_env("PORT", "4000") |> to_integer()
  ],
  url: [
    scheme: get_env("URL_SCHEME", "http"),
    host: get_env("HOST", "localhost"),
    port: get_env("URL_PORT", "4000")
  ],
  secret_key_base: secret.("SECRET_KEY_BASE", 64),
  live_view: [
    signing_salt: secret.("LIVE_VIEW_SIGNING_SALT", 24)
  ]

config :demo,
  dns_cluster_query: get_env("DNS_CLUSTER_QUERY"),
  analytics: get_env("ANALYTICS", "false") |> to_existing_atom()

config :logger, level: get_env("LOGGER_LEVEL", "debug") |> to_atom()

config :sentry,
  dsn: get_env("SENTRY_DSN"),
  environment_name: get_env("SENTRY_ENV", "local")

if config_env() == :test do
  config :demo, Demo.Repo, database: "test"

  config :demo, DemoWeb.Endpoint,
    http: [port: 4002],
    url: [port: 4002]

  config :logger, level: :warning
end
