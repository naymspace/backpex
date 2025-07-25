[
  line_length: 120,
  import_deps: [:ecto, :phoenix, :backpex, :ash, :ash_postgres],
  plugins: [Spark.Formatter, TailwindFormatter, Phoenix.LiveView.HTMLFormatter, Quokka],
  inputs: ["*.{heex,ex,exs}", "priv/*/seeds.exs", "{config,lib,test}/**/*.{heex,ex,exs}"],
  subdirectories: ["priv/*/migrations"]
]
