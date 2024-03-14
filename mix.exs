defmodule Backpex.MixProject do
  use Mix.Project

  @version "0.1.1"
  @source_url "https://github.com/naymspace/backpex"

  def project do
    [
      app: :backpex,
      version: @version,
      elixir: "~> 1.12",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),

      # Hex.pm
      package: package(),
      description: "Phoenix Admin Panel built with PETAL.",

      # Docs
      name: "Backpex",
      source_url: @source_url,
      homepage_url: "https://backpex.live",
      docs: docs()
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:ex_doc, "~> 0.23", only: [:dev, :test], runtime: false},
      {:phoenix, "~> 1.7.6"},
      {:phoenix_ecto, "~> 4.4"},
      {:ecto_sql, "~> 3.6"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_html, "~> 3.0"},
      {:phoenix_live_view, "~> 0.20.0"},
      {:floki, ">= 0.30.0"},
      {:gettext, "~> 0.18"},
      {:jason, "~> 1.2"},
      {:heroicons, "~> 0.5.0"},
      {:number, "~> 1.0.3"},
      {:credo, "~> 1.6.1", only: [:dev, :test], runtime: false},
      {:mix_audit, "~> 2.0", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.8", only: [:dev, :test]},
      {:money, "~> 1.12.1"},
      {:tailwind_formatter, "~> 0.4.0", only: [:dev, :test], runtime: false}
    ]
  end

  defp package do
    [
      files: ~w(lib priv mix.exs README.md LICENSE.md),
      maintainers: ["Florian Arens", "Phil-Bastian Berndt", "Simon Hansen"],
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end

  defp aliases do
    [
      lint: ["format --check-formatted", "credo", "sobelow --config"]
    ]
  end

  defp docs() do
    [
      logo: "priv/static/images/logo.svg",
      extras: extras(),
      extra_section: "GUIDES",
      groups_for_extras: groups_for_extras(),
      groups_for_modules: groups_for_modules(),
      groups_for_functions: [
        Components: &(&1[:type] == :component)
      ],
      source_ref: "develop",
      source_url_pattern: "#{@source_url}/blob/develop/%{path}#L%{line}"
    ]
  end

  defp extras do
    [
      "guides/introduction/installation.md",
      "guides/introduction/translations.md",
      "guides/advanced/full_text_search.md",
      "guides/upgrading/v0.2.md"
    ]
  end

  defp groups_for_extras do
    [
      Introduction: ~r/guides\/introduction\/.?/,
      Advanced: ~r/guides\/advanced\/.?/,
      "Upgrade Guides": ~r{guides/upgrading/.*}
    ]
  end

  defp groups_for_modules do
    [
      Components: ~r/Backpex\.HTML.?/,
      Fields: ~r/Backpex\.Field.?/,
      "Item Actions": ~r/Backpex\.ItemAction.?/,
      Filters: ~r/Backpex\.Filter.?/,
      Metrics: ~r/Backpex\.Metric.?/
    ]
  end
end
