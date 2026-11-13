# quokka:skip-module-directive-reordering
defmodule Backpex.Fields.MultiSelect do
  @config_schema [
    options: [
      doc: "List of possibly grouped options or function that receives the assigns.",
      type: {:or, [{:list, :any}, {:map, :any, :any}, {:fun, 1}]},
      required: true
    ],
    prompt: [
      doc: "The text to be displayed when no option is selected or function that receives the assigns.",
      type: {:or, [:string, {:fun, 1}]}
    ],
    not_found_text: [
      doc: """
      The text to be displayed when no options are found.

      The default value is `"No options found"`.
      """,
      type: :string
    ]
  ]

  @moduledoc """
  A field for handling a multi select with predefined options.

  The form renders a `Backpex.HTML.Combobox.combobox/1` with a search input and buttons to select and deselect all
  options. The admin selects and deselects options in the browser, and the selection reaches the server with the
  `phx-change` event of the form.

  This field can not be searchable.

  ## Field-specific options

  See `Backpex.Field` for general field options.

  #{NimbleOptions.docs(@config_schema)}

  ## Example

      @impl Backpex.LiveResource
      def fields do
        [
          users: %{
            module: Backpex.Fields.MultiSelect,
            label: "Users",
            options: fn _assigns -> [{"Alex", "user_id_alex"}, {"Bob", "user_id_bob"}] end
          },
        ]
  """
  use Backpex.Field, config_schema: @config_schema

  alias Backpex.HTML.Combobox

  require Backpex

  @impl Phoenix.LiveComponent
  def update(assigns, socket) do
    socket
    |> assign(assigns)
    |> assign(
      :not_found_text,
      assigns.field_options[:not_found_text] || Backpex.__("No options found", assigns.live_resource)
    )
    |> assign(:prompt, prompt(assigns, assigns.field_options))
    |> assign_options()
    |> assign_selected()
    |> ok()
  end

  defp assign_options(socket) do
    %{assigns: %{field_options: field_options} = assigns} = socket

    options =
      case Map.get(field_options, :options) do
        options when is_function(options) -> options.(assigns)
        options -> options
      end

    options =
      options
      |> Enum.map(fn {label, value} ->
        case value do
          value when is_list(value) or is_map(value) ->
            {to_string(label), Enum.map(value, fn {lab, val} -> {to_string(lab), to_string(val)} end)}

          value ->
            {to_string(label), to_string(value)}
        end
      end)

    assign(socket, :options, options)
  end

  defp flatten_options(options) do
    Enum.map(options, fn {_label, value} = option ->
      case value do
        value when is_list(value) or is_map(value) -> value
        _value -> option
      end
    end)
    |> List.flatten()
  end

  defp assign_selected(socket) do
    %{assigns: %{type: type, options: options, item: item, name: name} = assigns} = socket

    options = flatten_options(options)

    selected_ids =
      if type == :form do
        case PhoenixForm.input_value(assigns.form, name) do
          value when is_binary(value) -> [value]
          value when is_list(value) -> value
          _value -> []
        end
      else
        Map.get(item, name) || []
      end

    selected_ids = Enum.map(selected_ids, &to_string/1)

    selected = Enum.filter(options, fn {_label, value} -> value in selected_ids end)

    assign(socket, :selected, selected)
  end

  @impl Backpex.Field
  def render_value(assigns) do
    selected_labels = Enum.map(assigns.selected, fn {label, _value} = _option -> label end)

    assigns = assign(assigns, :selected_labels, selected_labels)

    ~H"""
    <div class={[@live_action in [:index, :resource_action] && "truncate"]}>
      {if @selected_labels == [], do: raw("&mdash;")}
      <div class="space-x-1">
        <div :for={item <- @selected_labels} class="badge badge-sm badge-soft badge-primary">
          <span>{HTML.pretty_value(item)}</span>
        </div>
      </div>
    </div>
    """
  end

  @impl Backpex.Field
  def render_form(assigns) do
    assigns = assign(assigns, :label_id, "#{assigns.form[assigns.name].id}-label")

    ~H"""
    <div id={@name}>
      <Layout.field_container>
        <:label :if={not @hide_label} align={Backpex.Field.align_label(@field_options, assigns)}>
          <Layout.input_label id={@label_id} for={"#{@form[@name].id}-trigger"} text={@field_options[:label]} />
        </:label>
        <Combobox.combobox
          field={@form[@name]}
          options={@options}
          multiple
          select_all
          readonly={@readonly}
          placeholder={@prompt}
          no_results_text={@not_found_text}
          translate_error_fun={Backpex.Field.translate_error_fun(@field_options, assigns)}
          help_text={Backpex.Field.help_text(@field_options, assigns)}
          live_resource={@live_resource}
          {Backpex.Field.label_attrs(assigns, @label_id)}
        />
      </Layout.field_container>
    </div>
    """
  end

  defp prompt(assigns, field_options) do
    case Map.get(field_options, :prompt) do
      nil -> Backpex.__("Select options...", assigns.live_resource)
      prompt when is_function(prompt) -> prompt.(assigns)
      prompt -> prompt
    end
  end
end
