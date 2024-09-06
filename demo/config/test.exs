import Config

config :libcluster,
  topologies: [
    app: [
      strategy: Elixir.Cluster.Strategy.Epmd,
      config: [
        hosts: [:nonode@nohost]
      ]
    ]
  ]

config :demo, DemoWeb.Endpoint, server: false

config :demo, Demo.Repo, pool: Ecto.Adapters.SQL.Sandbox

config :phoenix, :plug_init_mode, :runtime

config :phoenix_test, :endpoint, DemoWeb.Endpoint
