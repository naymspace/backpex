defmodule Backpex.Fields.FormInputOptionsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Backpex.Fields

  defmodule EmptyAdapter do
    @moduledoc false
    def read(_query), do: {:ok, []}
  end

  defmodule CategoryLive do
    @moduledoc false
    def config(:adapter), do: EmptyAdapter
  end

  defmodule ItemLive do
    @moduledoc false
    def config(:primary_key), do: :id
  end

  @belongs_to_assigns [
    live_resource: CategoryLive,
    owner_key: :category_id,
    display_field_form: :name
  ]

  @index_form_assigns [item: %{id: 1}, live_resource: ItemLive, value: nil]

  # {field module, render function, field name, required field options, extra assigns, id of the rendered input}
  @fields [
    {Fields.BelongsTo, :render_form, :category, [display_field: :name], @belongs_to_assigns, "change_category_id"},
    {Fields.Boolean, :render_form, :value, [], [], "change_value"},
    {Fields.Boolean, :render_index_form, :value, [], @index_form_assigns, "index-form-input-value-1"},
    {Fields.Currency, :render_form, :value, [], [], "change_value"},
    {Fields.Date, :render_form, :value, [], [], "change_value"},
    {Fields.DateTime, :render_form, :value, [], [], "change_value"},
    {Fields.Email, :render_form, :value, [], [], "change_value"},
    {Fields.Number, :render_form, :value, [], [], "change_value"},
    {Fields.Select, :render_form, :value, [options: [A: "a"]], [], "change_value"},
    {Fields.Text, :render_form, :value, [], [], "change_value"},
    {Fields.Textarea, :render_form, :value, [], [], "change_value"},
    {Fields.Time, :render_form, :value, [], [], "change_value"},
    {Fields.URL, :render_form, :value, [], [], "change_value"}
  ]

  describe "debounce and throttle" do
    for {module, fun, name, required_options, extra_assigns, input_id} <- @fields do
      @module module
      @fun fun
      @name name
      @required_options required_options
      @extra_assigns extra_assigns
      @input_id input_id

      test "#{inspect(module)}.#{fun}/1 renders them on the input" do
        for {options, debounce, throttle} <- debounce_throttle_cases() do
          doc = render(@module, @fun, @name, @required_options ++ options, @extra_assigns)

          assert attribute_by_id(doc, "phx-debounce") == List.wrap(debounce && {@input_id, debounce}),
                 "phx-debounce for #{inspect(options)}"

          assert attribute_by_id(doc, "phx-throttle") == List.wrap(throttle && {@input_id, throttle}),
                 "phx-throttle for #{inspect(options)}"
        end
      end
    end
  end

  describe "placeholder" do
    for {module, fun, extra_assigns, input_id} <- [
          {Fields.Email, :render_form, [], "change_value"},
          {Fields.Email, :render_index_form, @index_form_assigns, "index-form-input-value-1"},
          {Fields.Number, :render_form, [], "change_value"},
          {Fields.Number, :render_index_form, @index_form_assigns, "index-form-input-value-1"},
          {Fields.Text, :render_form, [], "change_value"},
          {Fields.Text, :render_index_form, @index_form_assigns, "index-form-input-value-1"},
          {Fields.Textarea, :render_form, [], "change_value"},
          {Fields.URL, :render_form, [], "change_value"}
        ] do
      @module module
      @fun fun
      @extra_assigns extra_assigns
      @input_id input_id

      test "#{inspect(module)}.#{fun}/1 renders it on the input" do
        doc = render(@module, @fun, :value, [placeholder: "Enter a value"], @extra_assigns)
        assert attribute_by_id(doc, "placeholder") == [{@input_id, "Enter a value"}]

        assert @module |> render(@fun, :value, [], @extra_assigns) |> attribute_by_id("placeholder") == []
      end

      test "#{inspect(module)}.#{fun}/1 renders the result of a function on the input" do
        doc =
          render(@module, @fun, :value, [placeholder: fn %{readonly: false} -> "From a function" end], @extra_assigns)

        assert attribute_by_id(doc, "placeholder") == [{@input_id, "From a function"}]
      end
    end
  end

  describe "rows" do
    test "Backpex.Fields.Textarea.render_form/1 renders them on the textarea" do
      assert Fields.Textarea |> render(:render_form, :value, [rows: 5], []) |> attribute_by_id("rows") ==
               [{"change_value", "5"}]

      assert Fields.Textarea |> render(:render_form, :value, [], []) |> attribute_by_id("rows") == [
               {"change_value", "2"}
             ]
    end
  end

  describe "help_text" do
    for {module, :render_form, name, required_options, extra_assigns, _input_id} <- @fields do
      @module module
      @name name
      @required_options required_options
      @extra_assigns extra_assigns

      test "#{inspect(module)}.render_form/1 renders a string or the result of a function below the input" do
        for {options, expected} <- [
              {[], []},
              {[help_text: "Help text"], ["Help text"]},
              {[help_text: fn %{readonly: false} -> "Help from a function" end], ["Help from a function"]}
            ] do
          doc = render(@module, :render_form, @name, @required_options ++ options, @extra_assigns)

          assert doc
                 |> LazyHTML.query("p.text-base-content\\/60")
                 |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim())) == expected,
                 "help text for #{inspect(options)}"
        end
      end
    end
  end

  describe "align_label" do
    for {module, :render_form, name, required_options, extra_assigns, _input_id} <- @fields do
      @module module
      @name name
      @required_options required_options
      @extra_assigns extra_assigns

      test "#{inspect(module)}.render_form/1 aligns the label to a value or the result of a function" do
        for {options, expected} <- [
              {[align_label: :top], "sm:self-start"},
              {[align_label: :center], "sm:self-center"},
              {[align_label: :bottom], "sm:self-end"},
              {[align_label: fn %{readonly: false} -> :bottom end], "sm:self-end"}
            ] do
          [class] =
            @module
            |> render(:render_form, @name, @required_options ++ options, @extra_assigns)
            |> LazyHTML.query("dl > dt")
            |> LazyHTML.attribute("class")

          assert expected in String.split(class), "label alignment for #{inspect(options)}"
        end
      end
    end
  end

  # {field options, expected phx-debounce, expected phx-throttle}
  defp debounce_throttle_cases do
    [
      {[], nil, nil},
      {[debounce: 300], "300", nil},
      {[debounce: "blur"], "blur", nil},
      {[debounce: fn %{readonly: false} -> 400 end], "400", nil},
      {[throttle: 500], nil, "500"},
      {[throttle: fn %{readonly: false} -> 600 end], nil, "600"},
      {[debounce: 700, throttle: 800], "700", "800"}
    ]
  end

  # Validates the options like a LiveResource does, so the field's config schema must accept them.
  defp render(module, fun, name, options, extra_assigns) do
    field_options =
      {name, [module: module, label: "Field"] ++ options}
      |> module.validate_config!(__MODULE__)
      |> Map.new()

    assigns =
      [
        name: name,
        field: {name, field_options},
        field_options: field_options,
        form: Phoenix.Component.to_form(%{}, as: :change),
        readonly: false,
        hide_label: false
      ] ++ extra_assigns

    module
    |> Function.capture(fun, 1)
    |> render_component(assigns)
    |> LazyHTML.from_fragment()
  end

  # Returns `{id, value}` of every element that has the attribute.
  defp attribute_by_id(doc, attribute) do
    doc
    |> LazyHTML.query("[#{attribute}]")
    |> Enum.map(fn element ->
      [id] = LazyHTML.attribute(element, "id")
      [value] = LazyHTML.attribute(element, attribute)
      {id, value}
    end)
  end
end
