defmodule Backpex.Fields.InlineCRUDTest do
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [to_form: 2]
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Backpex.Fields.InlineCRUD

  defmodule Link do
    @moduledoc false
    use Ecto.Schema

    embedded_schema do
      field :url, :string
    end
  end

  defmodule Product do
    @moduledoc false
    use Ecto.Schema

    schema "products" do
      embeds_many :links, Link, on_replace: :delete
    end
  end

  # A LiveResource that returns Backpex's texts untranslated, with their bindings filled in.
  defmodule UntranslatedLive do
    @moduledoc false
    def translate({msg, opts}) do
      Enum.reduce(opts, msg, fn {key, value}, msg -> String.replace(msg, "%{#{key}}", to_string(value)) end)
    end
  end

  defp render_form(overrides \\ []) do
    product = %Product{links: [%Link{id: "a", url: "https://a.example"}, %Link{id: "b", url: "https://b.example"}]}
    form = product |> Ecto.Changeset.change() |> to_form(as: :change)

    assigns =
      Keyword.merge(
        [
          form: form,
          name: :links,
          field_options: %{label: "Links"},
          child_fields: [],
          readonly: false,
          live_resource: UntranslatedLive,
          errors: []
        ],
        overrides
      )

    render_component(&InlineCRUD.render_form/1, assigns)
    |> LazyHTML.from_fragment()
  end

  describe "render_form/1" do
    test "renders a focusable, labelled delete button per row that drops the row" do
      buttons = LazyHTML.query(render_form(), "button[name='change[links_delete][]']")

      assert Enum.count(buttons) == 2
      assert LazyHTML.attribute(buttons, "type") == ["button", "button"]
      assert LazyHTML.attribute(buttons, "value") == ["0", "1"]
      assert LazyHTML.attribute(buttons, "aria-label") == ["Delete entry 1", "Delete entry 2"]
      assert LazyHTML.attribute(buttons, "tabindex") == []

      for click <- LazyHTML.attribute(buttons, "phx-click") do
        assert click =~ ~s("dispatch")
        assert click =~ ~s("change")
      end
    end

    test "does not render the delete control as a hidden checkbox" do
      assert render_form() |> LazyHTML.query("input[type=checkbox][name='change[links_delete][]']") |> Enum.empty?()
    end

    test "renders no delete buttons when readonly" do
      assert render_form(readonly: true) |> LazyHTML.query("button[name='change[links_delete][]']") |> Enum.empty?()
    end
  end
end
