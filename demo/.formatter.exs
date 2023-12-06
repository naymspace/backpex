[
  line_length: 120,
  import_deps: [:ecto, :phoenix, :backpex],
  plugins: [TailwindFormatter, Phoenix.LiveView.HTMLFormatter],
  inputs: ["*.{heex,ex,exs}", "priv/*/seeds.exs", "{config,lib,test}/**/*.{heex,ex,exs}"]
]
