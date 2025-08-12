defmodule Backpex.MixProject do
  use Mix.Project

  @version "0.14.0"

  @source_url "https://github.com/naymspace/backpex"
  @changelog_url "https://github.com/naymspace/backpex/releases"
  @website_url "https://backpex.live"

  def project do
    [
      app: :backpex,
      version: @version,
      elixir: "~> 1.16",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      gettext: gettext(),

      # Hex.pm
      package: package(),
      description: "Highly customizable administration panel for Phoenix LiveView applications.",

      # Docs
      name: "Backpex",
      source_url: @source_url,
      homepage_url: @website_url,
      docs: docs()
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # development
      {:ex_doc, "~> 0.38", only: [:dev, :test], runtime: false},
      {:makeup_eex, "~> 2.0", only: [:dev, :test], runtime: false},
      {:makeup_syntect, "~> 0.1.3", only: [:dev, :test], runtime: false},
      {:credo, ">= 0.0.0", only: [:dev, :test], runtime: false},
      {:mix_audit, "~> 2.0", only: [:dev, :test], runtime: false},
      {:tailwind_formatter, "~> 0.4", only: [:dev, :test], runtime: false},
      {:sobelow, ">= 0.0.0", only: [:dev, :test]},

      # core
      {:nimble_options, "~> 1.1"},
      {:gettext, "~> 0.26"},
      {:jason, "~> 1.2"},
      {:number, "~> 1.0"},
      {:money, "~> 1.13"},

      # phoenix
      {:phoenix, "~> 1.7.6"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_html_helpers, "~> 1.0"},
      {:phoenix_live_view, "~> 1.0"},

      # adapters
      {:ecto_sql, "~> 3.6"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_ecto, "~> 4.4"},
      {:ash, "~> 3.0", optional: true},
      {:ash_postgres, "~> 2.0", optional: true},

      # generators
      {:igniter, "~> 0.6"},
      {:igniter_js, "~> 0.4"}
    ]
  end

  defp package do
    [
      files: ~w(assets/js package.json lib priv .formatter.exs mix.exs README.md LICENSE.md),
      maintainers: ["Florian Arens", "Phil-Bastian Berndt", "Simon Hansen"],
      licenses: ["MIT"],
      links: %{
        Changelog: @changelog_url,
        GitHub: @source_url,
        Website: @website_url
      }
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
      source_url: @source_url,
      before_closing_head_tag: fn type ->
        if type == :html do
          """
          <script>
            if (location.hostname === "hexdocs.pm") {
              const script = document.createElement("script");
              script.src = "https://plausible.io/js/script.js";
              script.defer = true;
              script.setAttribute("data-domain", "hexdocs.pm/backpex");
              document.head.appendChild(script);
            }
          </script>
          """
        end
      end,
      skip_code_autolink_to: [
        "Ecto.Query.DynamicExpr"
      ]
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
      "guides/live_resource/on_mount-hook.md",
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
      "guides/translations/translations.md",

      # Upgrade Guides
      "guides/upgrading/v0.15.md",
      "guides/upgrading/v0.14.md",
      "guides/upgrading/v0.13.md",
      "guides/upgrading/v0.12.md",
      "guides/upgrading/v0.11.md",
      "guides/upgrading/v0.10.md",
      "guides/upgrading/v0.9.md",
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

  defp gettext() do
    [
      write_reference_comments: false,
      sort_by_msgid: :case_insensitive
    ]
  end
end
