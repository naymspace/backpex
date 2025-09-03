import Config

config :spark,
  formatter: [
    remove_parens?: true,
    "Ash.Resource": [
      section_order: [
        :postgres,
        :resource,
        :code_interface,
        :actions,
        :policies,
        :pub_sub,
        :preparations,
        :changes,
        :validations,
        :multitenancy,
        :attributes,
        :relationships,
        :calculations,
        :aggregates,
        :identities
      ]
    ],
    "Ash.Domain": [section_order: [:resources, :policies, :authorization, :domain, :execution]]
  ]

config :demo,
  namespace: Demo,
  ecto_repos: [Demo.Repo],
  ash_domains: [Demo.Helpdesk],
  generators: [binary_id: true]

config :demo, DemoWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  url: [host: "localhost"],
  render_errors: [
    formats: [html: DemoWeb.ErrorHTML],
    layout: false
  ],
  pubsub_server: Demo.PubSub

config :demo, Demo.Repo, migration_primary_key: [name: :id, type: :binary_id]

config :esbuild,
  version: "0.25.9",
  default: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=. --alias:backpex=/opt/app),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ],
  backpex: [
    args: ~w(../assets/js/backpex.js --bundle --format=esm --sourcemap --outfile=priv/static/js/backpex.esm.js),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

config :tailwind,
  version: "4.1.12",
  default: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :sentry,
  enable_source_code_context: true,
  root_source_code_paths: [File.cwd!()]

config :phoenix, :json_library, Jason

config :demo, DemoWeb.Gettext, default_locale: "en"

config :ash, include_embedded_source_by_default?: false, default_page_type: :keyset

config :ash, :policies, no_filter_static_forbidden_reads?: false

config :backpex,
  pubsub_server: Demo.PubSub,
  translator_function: {DemoWeb.CoreComponents, :translate_backpex},
  error_translator_function: {DemoWeb.CoreComponents, :translate_error}

import_config "#{config_env()}.exs"
