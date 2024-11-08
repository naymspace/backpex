defmodule Backpex.Fields.Text do
  @moduledoc """
  A field for handling a text value.

  ## Options

  * `:placeholder` - Optional placeholder value or function that receives the assigns.
  * `:debounce` - Optional integer timeout value (in milliseconds), "blur" or function that receives the assigns.
  * `:throttle` - Optional integer timeout value (in milliseconds) or function that receives the assigns.
  """
  use BackpexWeb, :field

  @impl Backpex.Field
  def render_value(assigns) do
    ~H"""
    <p class={@live_action in [:index, :resource_action] && "truncate"}>
      <%= HTML.pretty_value(@value) %>
    </p>
    """
  end

  @impl Backpex.Field
  def render_form(assigns) do
    ~H"""
    <div>
      <Layout.field_container>
        <:label align={Backpex.Field.align_label(@field_options, assigns, :center)}>
          <Layout.input_label text={@field_options[:label]} />
        </:label>
        <BackpexForm.input
          type="text"
          field={@form[@name]}
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
        <:label align={Backpex.Field.align_label(@field_options, assigns, :center)}>
          <Layout.input_label text={@field_options[:label]} />
        </:label>
        <BackpexForm.input
          type="text"
          field={@form[@name]}
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
          input_class={["input input-sm", @valid && "hover:input-bordered", !@valid && "input-error bg-error/10"]}
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
end
