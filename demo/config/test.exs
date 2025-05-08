import Config

config :demo, DemoWeb.Endpoint, server: false

config :demo, Demo.Repo, pool: Ecto.Adapters.SQL.Sandbox

config :phoenix, :plug_init_mode, :runtime

config :phoenix_test,
  endpoint: DemoWeb.Endpoint,
  otp_app: :demo,
  playwright: [
    cli: "node_modules/playwright/cli.js",
    browser: :chromium,
    browser_launch_timeout: 10_000,
    trace: System.get_env("PW_TRACE", "false") in ~w(t true)
  ]

config :demo, DemoWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "Ak58iOj9S792DBPi/oaAd+fsg6WdMiU10YfZAXGVz5ItCPbUGYHyvHiLvu2u0nGc",
  server: true,
  live_view: [signing_salt: "GD16mZjn72cumxHE"]
