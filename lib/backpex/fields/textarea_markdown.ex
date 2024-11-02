defmodule Backpex.Fields.TextareaMarkdown do
  @moduledoc """
  A field for handling long text values.

  ## Options

  * `:placeholder` - Optional placeholder value or function that receives the assigns.
  * `:debounce` - Optional integer timeout value (in milliseconds), "blur" or function that receives the assigns.
  * `:throttle` - Optional integer timeout value (in milliseconds) or function that receives the assigns.
  """
  use BackpexWeb, :field

  @impl Backpex.Field
  def render_value(assigns) do
    ~H"""
    <p
      class={[
        @live_action in [:index, :resource_action] && "truncate",
        @live_action == :show && "overflow-x-auto whitespace-pre-wrap"
      ]}
      phx-no-format
    ><%= HTML.pretty_value(@value) %></p>
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
        <BackpexForm.field_input
          type="textarea"
          field={@form[@name]}
          field_options={@field_options}
          input_class="min-h-[200px]"
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
        <:label align={Backpex.Field.align_label(@field_options, assigns, :top)}>
          <Layout.input_label text={@field_options[:label]} />
        </:label>
        <BackpexForm.field_input type="textarea" field={@form[@name]} field_options={@field_options} readonly disabled />
      </Layout.field_container>
    </div>
    """
  end
end
