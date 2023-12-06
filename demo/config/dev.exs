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

config :demo, Demo.Repo,
  show_sensitive_data_on_connection_error: true,
  migration_timestamps: [type: :utc_datetime]

config :phoenix_live_reload, :dirs, [Path.expand("../..", __DIR__)]

config :demo, DemoWeb.Endpoint,
  debug_errors: true,
  code_reloader: true,
  check_origin: false,
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:default, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:default, ~w(--watch)]}
  ],
  live_reload: [
    patterns: [
      ~r"demo/priv/static/.*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"demo/priv/gettext/.*(po)$",
      ~r"demo/lib/demo_web/helpers.ex$",
      ~r"demo/lib/demo_web/(live|views)/.*(ex)$",
      ~r"demo/lib/demo_web/templates/.*(eex)$",
      ~r"lib/backpex/(fields|html)/.*(ex)$"
    ]
  ],
  force_ssl: [hsts: true],
  http: [port: 4000],
  reloadable_apps: [:demo, :backpex]

config :logger, :console, format: "[$level] $message\n"

config :phoenix, :stacktrace_depth, 20

config :phoenix, :plug_init_mode, :runtime
