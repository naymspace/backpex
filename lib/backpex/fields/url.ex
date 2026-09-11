# quokka:skip-module-directive-reordering
defmodule Backpex.Fields.URL do
  @config_schema [
    placeholder: [
      doc: "Placeholder value or function that receives the assigns.",
      type: {:or, [:string, {:fun, 1}]}
    ],
    debounce: [
      doc: "Timeout value (in milliseconds), \"blur\" or function that receives the assigns.",
      type: {:or, [:pos_integer, :string, {:fun, 1}]}
    ],
    throttle: [
      doc: "Timeout value (in milliseconds) or function that receives the assigns.",
      type: {:or, [:pos_integer, {:fun, 1}]}
    ],
    allowed_schemes: [
      doc:
        "List of allowed schemes for the link (e.g. https). Values with disallowed scheme are displayed as raw text.",
      type: {:list, :string},
      default: ~w(https http tel mailto)
    ],
    anchor_text: [
      doc:
        "Anchor text to be displayed for the link on index and show views. Defaults to the URL. Can be a string or a function that receives the assigns.",
      type: {:or, [:string, {:fun, 1}]}
    ]
  ]

  @moduledoc """
  A field for handling an URL value.

  ## Field-specific options

  See `Backpex.Field` for general field options.

  #{NimbleOptions.docs(@config_schema)}
  """
  use Backpex.Field, config_schema: @config_schema

  @impl Backpex.Field
  def render_value(assigns) do
    assigns =
      assigns
      |> assign(:valid?, valid_url?(assigns.value, assigns.field_options))
      |> assign(:anchor_text, anchor_text(assigns.value, assigns.field_options, assigns))

    ~H"""
    <p class={@live_action in [:index, :resource_action] && "truncate"}>
      <.link :if={@valid?} href={@value} class="text-blue-600 underline">
        {@anchor_text}
      </.link>
      <span :if={!@valid?}>{@value}</span>
    </p>
    """
  end

  @impl Backpex.Field
  def render_form(assigns) do
    ~H"""
    <div>
      <Layout.field_container>
        <:label :if={not @hide_label} align={Backpex.Field.align_label(@field_options, assigns)}>
          <Layout.input_label for={@form[@name]} text={@field_options[:label]} />
        </:label>
        <BackpexForm.input
          type="text"
          field={@form[@name]}
          placeholder={@field_options[:placeholder]}
          translate_error_fun={Backpex.Field.translate_error_fun(@field_options, assigns)}
          help_text={Backpex.Field.help_text(@field_options, assigns)}
          phx-debounce={Backpex.Field.debounce(@field_options, assigns)}
          phx-throttle={Backpex.Field.throttle(@field_options, assigns)}
          aria-labelledby={Map.get(assigns, :aria_labelledby)}
          readonly={@readonly}
        />
      </Layout.field_container>
    </div>
    """
  end

  defp valid_url?(value, field_options) when is_binary(value) do
    case URI.new(value) do
      {:ok, %URI{scheme: scheme}} ->
        is_nil(scheme) or String.downcase(scheme) in field_options.allowed_schemes

      {:error, _part} ->
        false
    end
  end

  defp valid_url?(_value, _field_options), do: false

  defp anchor_text(_value, %{anchor_text: text}, _assigns) when is_binary(text), do: text
  defp anchor_text(_value, %{anchor_text: fun}, assigns) when is_function(fun, 1), do: fun.(assigns)
  defp anchor_text(value, _field_options, _assigns), do: value
end
