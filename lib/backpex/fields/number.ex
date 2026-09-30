# quokka:skip-module-directive-reordering
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
        <:label :if={not @hide_label} align={Backpex.Field.align_label(@field_options, assigns)}>
          <Layout.input_label for={@form[@name]} text={@field_options[:label]} />
        </:label>
        <BackpexForm.input
          type="number"
          field={@form[@name]}
          placeholder={@field_options[:placeholder]}
          translate_error_fun={Backpex.Field.translate_error_fun(@field_options, assigns)}
          phx-debounce={Backpex.Field.debounce(@field_options, assigns)}
          phx-throttle={Backpex.Field.throttle(@field_options, assigns)}
          readonly={@readonly}
          aria-labelledby={Map.get(assigns, :aria_labelledby)}
        />
      </Layout.field_container>
    </div>
    """
  end

  @impl Backpex.Field
  def render_index_form(assigns) do
    assigns = Backpex.Field.assign_index_form(assigns)

    ~H"""
    <div>
      <BackpexForm.index_form form={@form} name={@name} item={@item} live_resource={@live_resource} class="relative">
        <BackpexForm.input
          id={"index-form-input-#{@name}-#{LiveResource.primary_value(@item, @live_resource)}"}
          type="number"
          field={@form[:value]}
          placeholder={@field_options[:placeholder]}
          input_class={["input input-sm", @valid && "not-hover:input-ghost", !@valid && "input-error bg-error/10"]}
          phx-debounce="100"
          readonly={@readonly}
          hide_errors
          aria-label={@field_options[:label]}
        />
      </BackpexForm.index_form>
    </div>
    """
  end

  @impl Backpex.Field
  def index_editable_change({name, _field_options}, value, _assigns), do: %{name => value}

  @impl Backpex.Field
  def search_condition(schema_name, field_name, search_string) do
    dynamic(
      [{^schema_name, schema_name}],
      ilike(fragment("CAST(? AS TEXT)", schema_name |> field(^field_name)), ^search_string)
    )
  end
end
