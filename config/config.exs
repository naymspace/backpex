import Config

if Mix.env() == :dev do
  esbuild = fn args ->
    [
      args: ~w(./js/backpex --bundle) ++ args,
      cd: Path.expand("../assets", __DIR__),
      env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
    ]
  end

  config :esbuild,
    version: "0.25.10",
    module: esbuild.(~w(--format=esm --sourcemap --outfile=../priv/static/js/backpex.esm.js)),
    main: esbuild.(~w(--format=cjs --sourcemap --outfile=../priv/static/js/backpex.cjs.js))
end

import_config "#{config_env()}.exs"
