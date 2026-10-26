defmodule Backpex.Fields.NumberTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Backpex.Fields.Number

  describe "render_form/1" do
    test "renders a help text string" do
      assert render_form(help_text: "Whole numbers only") =~ "Whole numbers only"
    end

    test "renders the result of a help text function" do
      assert render_form(help_text: fn %{readonly: false} -> "From a function" end) =~ "From a function"
    end
  end

  defp render_form(options) do
    field_options =
      {:value, [module: Number, label: "Amount"] ++ options}
      |> Number.validate_config!(__MODULE__)
      |> Map.new()

    render_component(&Number.render_form/1,
      name: :value,
      field_options: field_options,
      form: Phoenix.Component.to_form(%{}, as: :change),
      readonly: false,
      hide_label: false
    )
  end
end
