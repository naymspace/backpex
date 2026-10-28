defmodule Backpex.Fields.URLTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Backpex.Fields.URL

  describe "allowed_schemes" do
    test "links values with an allowed scheme and renders the others as text" do
      field_options = field_options(allowed_schemes: ["ftp"])

      assert render_value("ftp://files.example/report.pdf", field_options) ==
               {:link, "ftp://files.example/report.pdf"}

      assert render_value("https://example.com", field_options) == {:text, "https://example.com"}
    end

    test "links values of any allowed scheme, in any case" do
      assert render_value("sms:+49123", field_options(allowed_schemes: ["sms"])) == {:link, "sms:+49123"}
      assert render_value("HTTPS://example.com", field_options([])) == {:link, "HTTPS://example.com"}

      assert render_value("ssh://host.example", field_options(allowed_schemes: ["SSH"])) ==
               {:link, "ssh://host.example"}
    end

    test "defaults to https, http, tel and mailto" do
      field_options = field_options([])

      for value <- ["https://example.com", "http://example.com", "tel:+49123", "mailto:jane@example.com"] do
        assert render_value(value, field_options) == {:link, value}
      end

      assert render_value("javascript:alert(1)", field_options) == {:text, "javascript:alert(1)"}
      assert render_value("ftp://files.example", field_options) == {:text, "ftp://files.example"}
    end

    test "renders disguised disallowed schemes as text" do
      field_options = field_options([])

      for value <- ["JavaScript:alert(1)", " javascript:alert(1)", "java\tscript:alert(1)", "data:text/html,x"] do
        assert {:text, _text} = render_value(value, field_options)
      end
    end

    test "links values without a scheme" do
      assert render_value("/posts/1", field_options([])) == {:link, "/posts/1"}
    end
  end

  # Validating the options like a LiveResource does fills in the defaults of the config schema.
  defp field_options(options) do
    {:url, Map.merge(%{module: URL, label: "URL"}, Map.new(options))}
    |> URL.validate_config!(__MODULE__)
    |> Map.new()
  end

  # Returns `{:link, href}` when the value is rendered as a link or `{:text, text}` otherwise.
  defp render_value(value, field_options) do
    html = render_component(&URL.render_value/1, value: value, field_options: field_options, live_action: :show)
    document = LazyHTML.from_fragment(html)

    links = document |> LazyHTML.query("a") |> Enum.to_list()

    case links do
      [link] ->
        [href] = LazyHTML.attribute(link, "href")
        {:link, href}

      [] ->
        {:text, document |> LazyHTML.query("span") |> LazyHTML.text() |> String.trim()}
    end
  end
end
