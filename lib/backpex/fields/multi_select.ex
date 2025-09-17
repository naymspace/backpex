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
  alias Backpex.HTML.Form
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
    |> assign(:search_input, "")
    |> assign_options()
    |> assign_selected()
    |> maybe_assign_form()
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

          _ ->
            {to_string(label), to_string(value)}
        end
      end)

    assign(socket, :options, options)
  end

  defp flatten_options(options) do
    Enum.map(options, fn {_label, value} = option ->
      case value do
        value when is_list(value) or is_map(value) -> value
        _ -> option
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
        Map.get(item, name, []) || []
      end

    selected_ids = Enum.map(selected_ids, &to_string/1)

    selected = Enum.filter(options, fn {_label, value} -> value in selected_ids end)

    assign(socket, :selected, selected)
  end

  defp maybe_assign_form(%{assigns: %{type: :form} = assigns} = socket) do
    %{selected: selected, options: options} = assigns

    options = flatten_options(options)

    show_select_all = length(selected) != length(options)

    socket
    |> assign(:search_input, "")
    |> assign(:show_select_all, show_select_all)
  end

  defp maybe_assign_form(socket), do: socket

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
    ~H"""
    <div id={@name}>
      <Layout.field_container>
        <:label align={Backpex.Field.align_label(@field_options, assigns)}>
          <Layout.input_label as="span" text={@field_options[:label]} />
        </:label>
        <Form.multi_select
          field={@form[@name]}
          prompt={@prompt}
          not_found_text={@not_found_text}
          options={@options}
          selected={@selected}
          search_input={@search_input}
          field_options={@field_options}
          show_select_all={@show_select_all}
          show_more={false}
          event_target={@myself}
          search_event="search"
          live_resource={@live_resource}
          help_text={Backpex.Field.help_text(@field_options, assigns)}
        />
      </Layout.field_container>
    </div>
    """
  end

  @impl Phoenix.LiveComponent
  def handle_event("toggle-option", %{"id" => id}, socket) do
    %{assigns: %{selected: selected, options: options}} = socket

    options = flatten_options(options)

    clicked_item = Enum.find(options, fn {_label, value} -> value == id end)

    new_selected =
      if clicked_item in selected do
        selected -- [clicked_item]
      else
        selected ++ [clicked_item]
      end

    show_select_all = length(new_selected) != length(options)

    socket
    |> assign(:selected, new_selected)
    |> assign(:show_select_all, show_select_all)
    |> noreply()
  end

  @impl Phoenix.LiveComponent
  def handle_event("search", params, socket) do
    socket = assign_options(socket)
    %{assigns: %{name: name, options: options}} = socket

    search_input = Map.get(params, "change[#{name}]_search")

    options = maybe_apply_search(options, search_input)

    socket
    |> assign(:options, options)
    |> assign(:search_input, search_input)
    |> noreply()
  end

  @impl Phoenix.LiveComponent
  def handle_event("toggle-select-all", _params, socket) do
    %{assigns: %{options: options, show_select_all: show_select_all}} = socket

    options = flatten_options(options)

    new_selected = if show_select_all, do: options, else: []

    socket
    |> assign(:selected, new_selected)
    |> assign(:show_select_all, not show_select_all)
    |> noreply()
  end

  defp maybe_apply_search(options, search_input) do
    if String.trim(search_input) == "" do
      options
    else
      search_input_downcase = String.downcase(search_input)

      keep? = fn label -> String.downcase(label) |> String.contains?(search_input_downcase) end

      Enum.map(options, fn {label, value} ->
        case value do
          value when is_list(value) or is_map(value) ->
            filtered = Enum.filter(value, fn {_lab, val} -> keep?.(val) end)
            if not Enum.empty?(filtered), do: {label, filtered}

          _ ->
            if keep?.(label), do: {label, value}
        end
      end)
      |> Enum.filter(& &1)
    end
  end

  defp prompt(assigns, field_options) do
    case Map.get(field_options, :prompt) do
      nil -> Backpex.__("Select options...", assigns.live_resource)
      prompt when is_function(prompt) -> prompt.(assigns)
      prompt -> prompt
    end
  end
end
