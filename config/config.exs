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
    version: "0.25.8",
    module: esbuild.(~w(--format=esm --sourcemap --outfile=../priv/static/js/backpex.esm.js)),
    main: esbuild.(~w(--format=cjs --sourcemap --outfile=../priv/static/js/backpex.cjs.js)),
    cdn: esbuild.(~w(--format=iife --target=es2016 --global-name=LiveView --outfile=../priv/static/js/backpex.js)),
    cdn_min:
      esbuild.(
        ~w(--format=iife --target=es2016 --global-name=LiveView --minify --outfile=../priv/static/js/backpex.min.js)
      )
end

import_config "#{config_env()}.exs"
