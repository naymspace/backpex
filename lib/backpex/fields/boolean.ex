defmodule Backpex.Fields.Boolean do
  @moduledoc """
  A field for handling a boolean value.

  ## Options

  * `:debounce` - Optional integer timeout value (in milliseconds), "blur" or function that receives the assigns.
  * `:throttle` - Optional integer timeout value (in milliseconds) or function that receives the assigns.
  """
  use BackpexWeb, :field

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
          type="toggle"
          field={@form[:value]}
          input_class={["toggle toggle-sm toggle-success", "hover:input-bordered"]}
          phx-debounce={Backpex.Field.debounce(@field_options, assigns)}
          phx-throttle={Backpex.Field.throttle(@field_options, assigns)}
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
