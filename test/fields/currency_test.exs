defmodule Backpex.Fields.CurrencyTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Backpex.Fields.Currency

  describe "render_form/1" do
    test "passes the defaults to the currency input hook" do
      assert hook_data([]) == %{
               "data-radix" => ".",
               "data-thousands-separator" => ",",
               "data-unit" => "$",
               "data-mask-pattern" => "$num"
             }
    end

    test "passes radix, thousands separator and unit to the currency input hook" do
      assert hook_data(radix: ",", thousands_separator: ".", unit: "€") == %{
               "data-radix" => ",",
               "data-thousands-separator" => ".",
               "data-unit" => "€",
               "data-mask-pattern" => "€num"
             }
    end

    for {unit_position, symbol_space, mask_pattern} <- [
          {:before, false, "€num"},
          {:before, true, "€ num"},
          {:after, false, "num€"},
          {:after, true, "num €"}
        ] do
      @options [unit: "€", unit_position: unit_position, symbol_space: symbol_space]
      @mask_pattern mask_pattern

      test "builds the mask pattern #{inspect(mask_pattern)} from unit_position #{unit_position} and symbol_space #{symbol_space}" do
        assert hook_data(@options)["data-mask-pattern"] == @mask_pattern
      end
    end
  end

  # Validates the options like a LiveResource does, so the defaults of the config schema apply.
  defp hook_data(options) do
    field_options =
      {:price, [module: Currency, label: "Price"] ++ options}
      |> Currency.validate_config!(__MODULE__)
      |> Map.new()

    html =
      render_component(&Currency.render_form/1,
        name: :price,
        field_options: field_options,
        form: Phoenix.Component.to_form(%{}, as: :change),
        readonly: false,
        hide_label: false
      )

    [hook] =
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(~s([phx-hook="BackpexCurrencyInput"]))
      |> Enum.to_list()

    Map.new(~w(data-radix data-thousands-separator data-unit data-mask-pattern), fn attribute ->
      {attribute, hook |> LazyHTML.attribute(attribute) |> List.first()}
    end)
  end
end
