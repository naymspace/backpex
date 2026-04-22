[
  line_length: 120,
  import_deps: [:ecto, :phoenix, :backpex],
  plugins: [Phoenix.LiveView.HTMLFormatter, Quokka],
  inputs: ["*.{heex,ex,exs}", "priv/*/seeds.exs", "{config,lib,test}/**/*.{heex,ex,exs}"],
  subdirectories: ["priv/*/migrations"],
  quokka: [
    exclude: [
      :module_directives
    ]
  ]
]
