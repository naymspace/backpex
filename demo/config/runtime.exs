import Config
import System, only: [get_env: 1, get_env: 2, fetch_env!: 1]
import String, only: [to_integer: 1, to_atom: 1, to_existing_atom: 1]

config :demo, Demo.Repo,
  hostname: get_env("DB_HOSTNAME", "postgres"),
  username: get_env("DB_USERNAME", "postgres"),
  password: get_env("DB_PASSWORD", "postgres"),
  database: get_env("DB_DATABASE", "postgres"),
  port: to_integer(get_env("DB_PORT", "5432")),
  pool_size: to_integer(get_env("DB_POOL_SIZE", "5"))

config :demo, DemoWeb.DashboardAuthPlug,
  enabled: to_existing_atom(get_env("DASHBOARD_AUTH_ENABLED", "false")),
  username: get_env("DASHBOARD_AUTH_USERNAME", "backpex"),
  password: get_env("DASHBOARD_AUTH_PASSWORD", "backpex")

config :demo, DemoWeb.Endpoint,
  http: [
    port: to_integer(get_env("PORT", "4000"))
  ],
  url: [
    scheme: get_env("URL_SCHEME", "http"),
    host: get_env("HOST", "localhost"),
    port: get_env("URL_PORT", "4000")
  ],
  secret_key_base: fetch_env!("SECRET_KEY_BASE"),
  live_view: [
    signing_salt: fetch_env!("LIVE_VIEW_SIGNING_SALT")
  ]

config :demo,
  dns_cluster_query: get_env("DNS_CLUSTER_QUERY"),
  analytics: to_existing_atom(get_env("ANALYTICS", "false"))

config :logger, level: to_atom(get_env("LOGGER_LEVEL", "debug"))

config :sentry,
  dsn: get_env("SENTRY_DSN"),
  environment_name: get_env("SENTRY_ENV", "local")
