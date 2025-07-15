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
    assigns = assign(assigns, :valid?, valid_url?(assigns.value, assigns.field_options))

    ~H"""
    <p class={@live_action in [:index, :resource_action] && "truncate"}>
      <.link :if={@valid?} href={@value} class="text-blue-600 underline">
        {@value}
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
        <:label align={Backpex.Field.align_label(@field_options, assigns)}>
          <Layout.input_label text={@field_options[:label]} />
        </:label>
        <BackpexForm.input
          type="text"
          field={@form[@name]}
          placeholder={@field_options[:placeholder]}
          translate_error_fun={Backpex.Field.translate_error_fun(@field_options, assigns)}
          help_text={Backpex.Field.help_text(@field_options, assigns)}
          phx-debounce={Backpex.Field.debounce(@field_options, assigns)}
          phx-throttle={Backpex.Field.throttle(@field_options, assigns)}
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
end
