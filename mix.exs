defmodule Backpex.MixProject do
  use Mix.Project

  @version "0.7.1"
  @source_url "https://github.com/naymspace/backpex"

  def project do
    [
      app: :backpex,
      version: @version,
      elixir: "~> 1.16",
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
      # development
      {:ex_doc, "~> 0.34", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7.5", only: [:dev, :test], runtime: false},
      {:mix_audit, "~> 2.0", only: [:dev, :test], runtime: false},
      {:tailwind_formatter, "~> 0.4.0", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.13", only: [:dev, :test]},

      # core
      {:nimble_options, "~> 1.1"},
      {:gettext, "~> 0.26"},
      {:jason, "~> 1.2"},
      {:number, "~> 1.0.3"},
      {:money, "~> 1.13.1"},

      # phoenix
      {:phoenix, "~> 1.7.6"},
      {:phoenix_html, "~> 4.1.1"},
      {:phoenix_html_helpers, "~> 1.0"},
      {:phoenix_live_view, "~> 0.20.0"},

      # adapters
      {:ecto_sql, "~> 3.6"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_ecto, "~> 4.4"},
      {:ash, "~> 3.0", optional: true},
      {:ash_postgres, "~> 2.0.0", optional: true}
    ]
  end

  defp package do
    [
      files: ~w(lib priv .formatter.exs mix.exs README.md LICENSE.md),
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
      main: "readme",
      logo: "priv/static/images/logo.svg",
      extras: extras(),
      extra_section: "GUIDES",
      groups_for_extras: groups_for_extras(),
      groups_for_modules: groups_for_modules(),
      groups_for_docs: [
        Components: &(&1[:type] == :component)
      ],
      source_ref: @version,
      source_url: @source_url
    ]
  end

  defp extras do
    [
      {"README.md", title: "Introduction"},

      # About
      "guides/about/what-is-backpex.md",
      "guides/about/why-we-built-backpex.md",
      "guides/about/contribute-to-backpex.md",

      # Get Started
      "guides/get_started/installation.md",

      # Live Resource
      "guides/live_resource/what-is-a-live-resource.md",
      "guides/live_resource/templates.md",
      "guides/live_resource/item-query.md",
      "guides/live_resource/ordering.md",
      "guides/live_resource/hooks.md",
      "guides/live_resource/navigation.md",
      "guides/live_resource/panels.md",
      "guides/live_resource/fluid-layout.md",
      "guides/live_resource/listen-to-pubsub-events.md",
      "guides/live_resource/additional-classes-for-index-table-rows.md",

      # Fields
      "guides/fields/what-is-a-field.md",
      "guides/fields/custom-fields.md",
      "guides/fields/alignment.md",
      "guides/fields/visibility.md",
      "guides/fields/defaults.md",
      "guides/fields/readonly.md",
      "guides/fields/custom-alias.md",
      "guides/fields/placeholder.md",
      "guides/fields/debounce-and-throttle.md",
      "guides/fields/index-edit.md",
      "guides/fields/error-customization.md",
      "guides/fields/computed-fields.md",

      # Filter
      "guides/filter/what-is-a-filter.md",
      "guides/filter/how-to-add-a-filter.md",
      "guides/filter/filter-presets.md",
      "guides/filter/custom-filter.md",
      "guides/filter/visibility-and-authorization.md",

      # Actions
      "guides/actions/item-actions.md",
      "guides/actions/resource-actions.md",

      # Authorization
      "guides/authorization/live-resource-authorization.md",
      "guides/authorization/field-authorization.md",

      # Searching
      "guides/searching/basic-search.md",
      "guides/searching/full-text-search.md",

      # Translations
      "guides/custom_labels_and_translations/custom-labels-and-translations.md",

      # Upgrade Guides
      "guides/upgrading/v0.8.md",
      "guides/upgrading/v0.7.md",
      "guides/upgrading/v0.6.md",
      "guides/upgrading/v0.5.md",
      "guides/upgrading/v0.3.md",
      "guides/upgrading/v0.2.md"
    ]
  end

  defp groups_for_extras do
    [
      Introduction: ~r/README/,
      About: ~r/guides\/about\/.?/,
      "Get Started": ~r/guides\/get_started\/.?/,
      "Live Resource": ~r/guides\/live_resource\/.?/,
      Fields: ~r/guides\/fields\/.?/,
      Filter: ~r/guides\/filter\/.?/,
      Actions: ~r/guides\/actions\/.?/,
      Authorization: ~r/guides\/authorization\/.?/,
      Searching: ~r/guides\/searching\/.?/,
      "Custom Labels and Translations": ~r/guides\/custom_labels_and_translations\/.?/,
      "Upgrade Guides": ~r{guides/upgrading/.*}
    ]
  end

  defp groups_for_modules do
    [
      Adapters: ~r/Backpex\.Adapter.?/,
      Components: ~r/Backpex\.HTML.?/,
      Fields: ~r/Backpex\.Field.?/,
      Actions: ~r/Backpex\.(ItemAction|ResourceAction).?/,
      Filters: ~r/Backpex\.Filter.?/,
      Metrics: ~r/Backpex\.Metric.?/
    ]
  end
end
