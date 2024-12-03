defmodule Backpex.Fields.Boolean do
  @config_schema []

  @moduledoc """
  A field for handling a boolean value.

  ## Field-specific options

  See `Backpex.Field` for general field options.

  #{NimbleOptions.docs(@config_schema)}
  """
  use Backpex.Field, config_schema: @config_schema

  @impl Backpex.Field
  def render_value(assigns) do
    ~H"""
    <div>
      <Backpex.HTML.CoreComponents.icon :if={@value} name="hero-check-solid" class="h-5 w-5 text-success" />
      <Backpex.HTML.CoreComponents.icon :if={!@value} name="hero-x-mark-solid" class="h-5 w-5 text-error" />
    </div>
    """
  end

  @impl Backpex.Field
  def render_form(assigns) do
    ~H"""
    <div>
      <Layout.field_container>
        <:label align={Backpex.Field.align_label(@field_options, assigns, :top)}>
          <Layout.input_label text={@field_options[:label]} />
        </:label>
        <BackpexForm.input
          type="toggle"
          field={@form[@name]}
          translate_error_fun={Backpex.Field.translate_error_fun(@field_options, assigns)}
          phx-debounce={Backpex.Field.debounce(@field_options, assigns)}
          phx-throttle={Backpex.Field.throttle(@field_options, assigns)}
        />
      </Layout.field_container>
    </div>
    """
  end
end
