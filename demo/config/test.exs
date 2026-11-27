import Config

config :demo, Demo.Repo, pool: Ecto.Adapters.SQL.Sandbox
config :demo, DemoWeb.Endpoint, server: true

config :fluffy, endpoint: DemoWeb.Endpoint

config :phoenix, :plug_init_mode, :runtime

config :phoenix_test,
  endpoint: DemoWeb.Endpoint,
  otp_app: :demo

config :playwright, :test,
  trace: if(System.get_env("PW_TRACE", "false") in ~w(t true), do: :on, else: :off),
  output_dir: "tmp"
