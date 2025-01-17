import Config

config :demo, DemoWeb.Endpoint, server: false

config :demo, Demo.Repo, pool: Ecto.Adapters.SQL.Sandbox

config :phoenix, :plug_init_mode, :runtime
