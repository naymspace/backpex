import Config

config :demo, DemoWeb.Endpoint,
  cache_static_manifest: "priv/static/cache_manifest.json",
  server: true

config :logger, backends: [:console, Sentry.LoggerBackend]
