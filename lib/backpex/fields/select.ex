defmodule Backpex.Fields.Select do
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
    debounce: [
      doc: "Timeout value (in milliseconds), \"blur\" or function that receives the assigns.",
      type: {:or, [:pos_integer, :string, {:fun, 1}]}
    ],
    throttle: [
      doc: "Timeout value (in milliseconds) or function that receives the assigns.",
      type: {:or, [:pos_integer, {:fun, 1}]}
    ]
  ]

  @moduledoc """
  A field for handling a select value.

  ## Field-specific options

  See `Backpex.Field` for general field options.

  #{NimbleOptions.docs(@config_schema)}

  ## Example

      @impl Backpex.LiveResource
      def fields do
        [
          role: %{
            module: Backpex.Fields.Select,
            label: "Role",
            options: [Admin: admin, User: user]
          }
        ]
      end
  """
  use Backpex.Field, config_schema: @config_schema

  @impl Backpex.Field
  def render_value(assigns) do
    options = get_options(assigns)
    label = get_label(assigns.value, options)

    assigns = assign(assigns, :label, label)

    ~H"""
    <p class={@live_action in [:index, :resource_action] && "truncate"}>
      {HTML.pretty_value(@label)}
    </p>
    """
  end

  @impl Backpex.Field
  def render_form(assigns) do
    options = get_options(assigns)

    assigns =
      assigns
      |> assign(:options, options)
      |> assign_prompt(assigns.field_options)

    ~H"""
    <div>
      <Layout.field_container>
        <:label align={Backpex.Field.align_label(@field_options, assigns)}>
          <Layout.input_label text={@field_options[:label]} />
        </:label>
        <BackpexForm.input
          type="select"
          field={@form[@name]}
          options={@options}
          prompt={@prompt}
          translate_error_fun={Backpex.Field.translate_error_fun(@field_options, assigns)}
          phx-debounce={Backpex.Field.debounce(@field_options, assigns)}
          phx-throttle={Backpex.Field.throttle(@field_options, assigns)}
        />
      </Layout.field_container>
    </div>
    """
  end

  @impl Backpex.Field
  def render_index_form(assigns) do
    form = to_form(%{"value" => assigns.value}, as: :index_form)
    options = get_options(assigns)

    assigns =
      assigns
      |> assign(:options, options)
      |> assign_new(:form, fn -> form end)
      |> assign_new(:valid, fn -> true end)
      |> assign_prompt(assigns.field_options)

    ~H"""
    <div>
      <.form for={@form} class="relative" phx-change="update-field" phx-submit="update-field" phx-target={@myself}>
        <BackpexForm.input
          type="select"
          field={@form[:value]}
          options={@options}
          prompt={@prompt}
          input_wrapper_class=""
          input_class={["select select-sm", if(@valid, do: "[:not(:hover)]:select-ghost", else: "select-error")]}
          disabled={@readonly}
          hide_errors
        />
      </.form>
    </div>
    """
  end

  @impl Phoenix.LiveComponent
  def handle_event("update-field", %{"index_form" => %{"value" => value}}, socket) do
    Backpex.Field.handle_index_editable(socket, value, Map.put(%{}, socket.assigns.name, value))
  end

  defp get_label(value, options) do
    case Enum.find(options, fn option -> value?(option, value) end) do
      nil -> value
      {label, _value} -> label
      label -> label
    end
  end

  defp value?({_label, value}, to_compare), do: to_string(value) == to_string(to_compare)
  defp value?(value, to_compare), do: to_string(value) == to_string(to_compare)

  defp assign_prompt(assigns, field_options) do
    prompt =
      case Map.get(field_options, :prompt) do
        nil -> nil
        prompt when is_function(prompt) -> prompt.(assigns)
        prompt -> prompt
      end

    assign(assigns, :prompt, prompt)
  end

  defp get_options(assigns) do
    case Map.get(assigns.field_options, :options) do
      options when is_function(options) -> options.(assigns)
      options -> options
    end
  end
end
