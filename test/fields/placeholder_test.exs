defmodule Backpex.Fields.PlaceholderTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Backpex.Fields

  defmodule ItemLive do
    @moduledoc false
    def config(:primary_key), do: :id
  end

  @index_form_assigns [item: %{id: 1}, live_resource: ItemLive, value: nil]

  # {field module, render function, extra assigns, id of the rendered input}
  @inputs [
    {Fields.Email, :render_form, [], "change_value"},
    {Fields.Email, :render_index_form, @index_form_assigns, "index-form-input-value-1"},
    {Fields.Number, :render_form, [], "change_value"},
    {Fields.Number, :render_index_form, @index_form_assigns, "index-form-input-value-1"},
    {Fields.Text, :render_form, [], "change_value"},
    {Fields.Text, :render_index_form, @index_form_assigns, "index-form-input-value-1"},
    {Fields.Textarea, :render_form, [], "change_value"},
    {Fields.URL, :render_form, [], "change_value"}
  ]

  for {module, fun, extra_assigns, input_id} <- @inputs do
    @module module
    @fun fun
    @extra_assigns extra_assigns
    @input_id input_id

    describe "#{inspect(module)}.#{fun}/1" do
      test "renders a placeholder string on the input" do
        assert placeholders(@module, @fun, [placeholder: "Enter a value"], @extra_assigns) == [
                 {@input_id, "Enter a value"}
               ]
      end

      test "renders the result of a placeholder function on the input" do
        placeholder = fn %{readonly: false} -> "From a function" end

        assert placeholders(@module, @fun, [placeholder: placeholder], @extra_assigns) == [
                 {@input_id, "From a function"}
               ]
      end

      test "renders no placeholder without the option" do
        assert placeholders(@module, @fun, [], @extra_assigns) == []
      end
    end
  end

  # Returns `{id, placeholder}` of every element with a placeholder.
  defp placeholders(module, fun, options, extra_assigns) do
    field_options =
      {:value, [module: module, label: "Field"] ++ options}
      |> module.validate_config!(__MODULE__)
      |> Map.new()

    assigns =
      [
        name: :value,
        field_options: field_options,
        form: Phoenix.Component.to_form(%{}, as: :change),
        readonly: false,
        hide_label: false
      ] ++ extra_assigns

    module
    |> Function.capture(fun, 1)
    |> render_component(assigns)
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("[placeholder]")
    |> Enum.map(fn element ->
      [id] = LazyHTML.attribute(element, "id")
      [placeholder] = LazyHTML.attribute(element, "placeholder")
      {id, placeholder}
    end)
  end
end
