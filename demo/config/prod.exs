import Config

config :demo, DemoWeb.Endpoint,
  cache_static_manifest: "priv/static/cache_manifest.json",
  server: true

config :demo, Demo.Repo,
  ssl: true,
  ssl_opts: [verify: :verify_none]

config :logger, backends: [:console, Sentry.LoggerBackend]
