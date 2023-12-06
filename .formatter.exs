locals_without_parens = [
  live_resources: 2,
  live_resources: 3
]

[
  line_length: 120,
  import_deps: [:ecto, :phoenix],
  plugins: [TailwindFormatter, Phoenix.LiveView.HTMLFormatter],
  inputs: ["*.{heex,ex,exs}", "priv/*/seeds.exs", "{config,lib,test}/**/*.{heex,ex,exs}"],
  subdirectories: ["priv/*/migrations"],
  locals_without_parens: locals_without_parens,
  export: [locals_without_parens: locals_without_parens]
]
