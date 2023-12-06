defmodule Backpex.Fields.URL do
  @moduledoc """
  A field for handling an URL value.

  ## Options

  * `:placeholder` - Optional placeholder value.
  * `:debounce` - Optional integer timeout value (in milliseconds), or "blur".
  * `:throttle` - Optional integer timeout value (in milliseconds).
  """
  use BackpexWeb, :field

  @impl Backpex.Field
  def render_value(assigns) do
    ~H"""
    <p class={@live_action in [:index, :resource_action] && "truncate"}>
      <.link href={@value} class="phx-no-feedback text-blue-600 underline">
        <%= @value %>
      </.link>
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
        <BackpexForm.field_input type="text" form={@form} field_name={@name} field_options={@field_options} />
      </Layout.field_container>
    </div>
    """
  end
end
