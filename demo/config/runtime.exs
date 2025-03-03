import Config
import System, only: [get_env: 1, get_env: 2, fetch_env!: 1]
import String, only: [to_integer: 1, to_atom: 1, to_existing_atom: 1]

config :demo,
  dns_cluster_query: get_env("DNS_CLUSTER_QUERY"),
  analytics: get_env("ANALYTICS", "false") |> to_existing_atom()

config :demo, Demo.Repo,
  hostname: get_env("DB_HOSTNAME", "localhost"),
  username: get_env("DB_USERNAME", "postgres"),
  password: get_env("DB_PASSWORD", "postgres"),
  database: get_env("DB_DATABASE", "postgres"),
  port: get_env("DB_PORT", "5432") |> to_integer(),
  pool_size: get_env("DB_POOL_SIZE", "5") |> to_integer()

config :demo, DemoWeb.Endpoint,
  http: [
    port: get_env("PORT", "4000") |> to_integer()
  ],
  url: [
    scheme: get_env("URL_SCHEME", "http"),
    host: get_env("HOST", "localhost"),
    port: get_env("URL_PORT", "4000")
  ],
  secret_key_base: "np5uHqUApBqAqesURR/sUlc0HJadx/4eBidnQ/w1bH/L1EiCdNlw1id9M/TrziRq",
  live_view: [
    signing_salt: "eYlXHghV/uji6ZNUhq+fb63bNVcps7CC"
  ]

config :demo, DemoWeb.DashboardAuthPlug,
  enabled: get_env("DASHBOARD_AUTH_ENABLED", "false") |> to_existing_atom(),
  username: get_env("DASHBOARD_AUTH_USERNAME", "backpex"),
  password: get_env("DASHBOARD_AUTH_PASSWORD", "backpex")

config :logger, level: get_env("LOGGER_LEVEL", "debug") |> to_atom()

config :sentry,
  dsn: get_env("SENTRY_DSN"),
  environment_name: get_env("SENTRY_ENV", "local")
