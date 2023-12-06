defmodule Backpex.Fields.Boolean do
  @moduledoc """
  A field for handling a boolean value.

  ## Options

  * `:debounce` - Optional integer timeout value (in milliseconds), or "blur".
  * `:throttle` - Optional integer timeout value (in milliseconds).
  """
  use BackpexWeb, :field

  @impl Backpex.Field
  def render_value(assigns) do
    ~H"""
    <div>
      <Heroicons.check :if={@value} solid class="h-5 w-5 text-green-500" />
      <Heroicons.x_mark :if={!@value} solid class="h-5 w-5 text-red-500" />
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
        <BackpexForm.field_input type="toggle" form={@form} field_name={@name} field_options={@field_options} />
        <BackpexForm.error_tag form={@form} name={@name} field_options={@field_options} />
      </Layout.field_container>
    </div>
    """
  end
end
