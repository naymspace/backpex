defmodule Backpex.Fields.MultiSelect do
  @config_schema [
    options: [
      doc: "List of options or function that receives the assigns.",
      type: {:or, [{:list, :any}, {:fun, 1}]},
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
      assigns
      |> field_options.options.()
      |> Enum.map(fn {label, value} ->
        {to_string(label), to_string(value)}
      end)

    assign(socket, :options, options)
  end

  defp assign_selected(socket) do
    %{assigns: %{type: type, options: options, item: item, name: name} = assigns} = socket

    selected_ids =
      if type == :form do
        values =
          case PhoenixForm.input_value(assigns.form, name) do
            value when is_binary(value) -> [value]
            value when is_list(value) -> value
            _value -> []
          end

        Enum.map(values, &to_string/1)
      else
        value = Map.get(item, name)

        if value, do: value, else: []
      end

    selected =
      Enum.reduce(options, [], fn {_label, value} = option, acc ->
        if value in selected_ids do
          [option | acc]
        else
          acc
        end
      end)
      |> Enum.reverse()

    assign(socket, :selected, selected)
  end

  defp maybe_assign_form(%{assigns: %{type: :form} = assigns} = socket) do
    %{selected: selected, options: options} = assigns

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

      <div class={["flex", @live_action == :show && "flex-wrap"]}>
        <.intersperse :let={item} enum={@selected_labels}>
          <:separator>
            ,&nbsp;
          </:separator>
          <p>
            {HTML.pretty_value(item)}
          </p>
        </.intersperse>
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
          <Layout.input_label text={@field_options[:label]} />
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
    %{assigns: %{selected: selected, options: options, field_options: field_options}} = socket

    selected_item = Enum.find(selected, fn {_label, value} -> value == id end)

    new_selected =
      if selected_item do
        Enum.reject(selected, fn {_label, value} -> value == id end)
      else
        selected
        |> Enum.reverse()
        |> Kernel.then(&[Enum.find(options, fn {_label, value} -> value == id end) | &1])
        |> Enum.reverse()
      end

    show_select_all = length(new_selected) != length(field_options.options.(socket.assigns))

    socket
    |> assign(:selected, new_selected)
    |> assign(:show_select_all, show_select_all)
    |> noreply()
  end

  @impl Phoenix.LiveComponent
  def handle_event("search", params, socket) do
    %{assigns: %{name: name, field_options: field_options} = assigns} = socket

    search_input = Map.get(params, "change[#{name}]_search")

    options =
      field_options.options.(assigns)
      |> maybe_apply_search(search_input)

    socket
    |> assign(:options, options)
    |> assign(:search_input, search_input)
    |> noreply()
  end

  @impl Phoenix.LiveComponent
  def handle_event("toggle-select-all", _params, socket) do
    %{assigns: %{field_options: field_options, show_select_all: show_select_all} = assigns} = socket

    new_selected = if show_select_all, do: field_options.options.(assigns), else: []

    socket
    |> assign(:selected, new_selected)
    |> assign(:show_select_all, not show_select_all)
    |> noreply()
  end

  defp maybe_apply_search(options, search_input) do
    if String.trim(search_input) != "" do
      search_input_downcase = String.downcase(search_input)

      Enum.filter(options, fn {label, _value} ->
        String.downcase(label)
        |> String.contains?(search_input_downcase)
      end)
    else
      options
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
