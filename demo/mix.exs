defmodule Demo.MixProject do
  use Mix.Project

  def project do
    [
      app: :demo,
      version: "0.0.0",
      elixir: "~> 1.12",
      elixirc_options: [warnings_as_errors: halt_on_warnings?(Mix.env())],
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: Mix.compilers(),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      gettext: gettext()
    ]
  end

  def application do
    [
      mod: {Demo.Application, []},
      extra_applications: [:logger, :runtime_tools, :os_mon]
    ]
  end

  defp halt_on_warnings?(:test), do: false
  defp halt_on_warnings?(:dev), do: false
  defp halt_on_warnings?(_), do: true

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(:dev), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # development
      {:ex_doc, "~> 0.37", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7.5", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.13", only: [:dev, :test]},
      {:mix_audit, "~> 2.0", only: [:dev, :test], runtime: false},
      {:tailwind_formatter, "~> 0.4.0", only: [:dev, :test], runtime: false},
      {:ex_machina, "~> 2.3"},
      {:faker, "~> 0.18"},
      {:phoenix_test, "~> 0.5.0", only: :test, runtime: false},
      {:sourceror, "~> 1.7", only: [:dev, :test]},

      # core
      {:dns_cluster, "~> 0.2.0"},
      {:telemetry_poller, "~> 1.0"},
      {:telemetry_metrics, "~> 1.0"},
      {:gettext, "~> 0.26"},
      {:sentry, "~> 10.8"},
      {:hackney, "~> 1.17", override: true},
      {:circular_buffer, "~> 0.4.0"},

      # phoenix
      {:bandit, "~> 1.0"},
      {:phoenix, "~> 1.7.6"},
      {:phoenix_pubsub, "~> 2.0"},
      {:phoenix_live_view, "~> 1.0"},
      {:phoenix_live_dashboard, "~> 0.8"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},

      # application
      {:backpex, path: "../."},
      {:phoenix_ecto, "~> 4.0"},
      {:ecto_sql, "~> 3.1"},
      {:postgrex, ">= 0.0.0"},
      {:ecto_psql_extras, "~> 0.8"},
      {:csv, "~> 3.2.0"},
      {:jason, ">= 1.0.0"},
      {:ash, "~> 3.0"},
      {:ash_postgres, "~> 2.5.0"},

      # assets
      {:esbuild, "~> 0.9", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.3.1", runtime: Mix.env() == :dev},
      {:heroicons, github: "tailwindlabs/heroicons", tag: "v2.2.0", sparse: "optimized", app: false, compile: false}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.seed": ["run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.rollback --all", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test --warnings-as-errors"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["tailwind default", "esbuild default"],
      "assets.deploy": ["tailwind default --minify", "esbuild default --minify", "phx.digest"]
    ]
  end

  defp gettext() do
    [
      write_reference_comments: false,
      sort_by_msgid: :case_insensitive
    ]
  end
end
