import Config

config :backpex,
  pubsub_server: Demo.PubSub,
  translator_function: {DemoWeb.CoreComponents, :translate_backpex},
  error_translator_function: {DemoWeb.CoreComponents, :translate_error}

config :demo, Demo.Repo, migration_primary_key: [name: :id, type: :binary_id]

config :demo, DemoWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  url: [host: "localhost"],
  render_errors: [
    formats: [html: DemoWeb.ErrorHTML],
    layout: false
  ],
  pubsub_server: Demo.PubSub

config :demo, DemoWeb.Gettext, default_locale: "en"

config :demo,
  namespace: Demo,
  ecto_repos: [Demo.Repo],
  generators: [binary_id: true]

config :esbuild,
  version: "0.28.0",
  default: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=. --alias:backpex=/opt/app),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ],
  backpex: [
    args: ~w(../assets/js/backpex.js --bundle --format=esm --sourcemap --outfile=priv/static/js/backpex.esm.js),
    cd: Path.expand("..", __DIR__)
  ]

config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :money,
  default_currency: :USD,
  separator: ",",
  delimiter: ".",
  symbol_on_right: false,
  symbol_space: false

config :phoenix, :json_library, Jason

config :sentry,
  enable_source_code_context: true,
  root_source_code_paths: [File.cwd!()]

config :tailwind,
  version: "4.2.4",
  default: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

import_config "#{config_env()}.exs"
