import Config

config :demo, Demo.Repo, pool: Ecto.Adapters.SQL.Sandbox
config :demo, DemoWeb.Endpoint, server: true

config :phoenix, :plug_init_mode, :runtime

config :phoenix_test,
  endpoint: DemoWeb.Endpoint,
  otp_app: :demo,
  playwright: [
    # directory containing node_modules
    assets_dir: "./",
    browser: :chromium,
    browser_launch_timeout: 10_000,
    trace: System.get_env("PW_TRACE", "false") in ~w(t true)
  ]
