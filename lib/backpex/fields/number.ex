defmodule Backpex.Fields.Number do
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
    readonly: [
      doc: "Sets the field to readonly. Also see the [panels](/guides/fields/readonly.md) guide.",
      type: {:or, [:boolean, {:fun, 1}]}
    ]
  ]

  @moduledoc """
  A field for handling a number value.

  ## Field-specific options

  See `Backpex.Field` for general field options.

  #{NimbleOptions.docs(@config_schema)}
  """
  use Backpex.Field, config_schema: @config_schema
  import Ecto.Query

  @impl Backpex.Field
  def render_value(assigns) do
    ~H"""
    <p class={@live_action in [:index, :resource_action] && "truncate"}>
      {HTML.pretty_value(@value)}
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
          phx-debounce={Backpex.Field.debounce(@field_options, assigns)}
          phx-throttle={Backpex.Field.throttle(@field_options, assigns)}
        />
      </Layout.field_container>
    </div>
    """
  end

  @impl Backpex.Field
  def render_form_readonly(assigns) do
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
          phx-debounce={Backpex.Field.debounce(@field_options, assigns)}
          phx-throttle={Backpex.Field.throttle(@field_options, assigns)}
          readonly
          disabled
        />
      </Layout.field_container>
    </div>
    """
  end

  @impl Backpex.Field
  def render_index_form(assigns) do
    form = to_form(%{"value" => assigns.value}, as: :index_form)

    assigns =
      assigns
      |> assign_new(:form, fn -> form end)
      |> assign_new(:valid, fn -> true end)

    ~H"""
    <div>
      <.form for={@form} class="relative" phx-change="update-field" phx-submit="update-field" phx-target={@myself}>
        <BackpexForm.input
          type="text"
          field={@form[:value]}
          placeholder={@field_options[:placeholder]}
          input_class={["input input-sm", @valid && "[:not(:hover)]:input-ghost", !@valid && "input-error bg-error/10"]}
          phx-debounce="100"
          readonly={@readonly}
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

  @impl Backpex.Field
  def search_condition(schema_name, field_name, search_string) do
    dynamic(
      [{^schema_name, schema_name}],
      ilike(fragment("CAST(? AS TEXT)", schema_name |> field(^field_name)), ^search_string)
    )
  end
end
