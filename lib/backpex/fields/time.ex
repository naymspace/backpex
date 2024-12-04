# credo:disable-for-this-file Credo.Check.Design.DuplicatedCode
defmodule Backpex.Fields.Time do
  @default_format "%I:%M %p"

  # credo:disable-for-next-line Credo.Check.Readability.StrictModuleLayout
  @moduledoc """
  A field for handling a time value.

  ## Options

    * `:format` - Format string which will be used to format the time value or function that formats the time.
      Defaults to `#{@default_format}`.
    * `:debounce` - Optional integer timeout value (in milliseconds), "blur" or function that receives the assigns.
    * `:throttle` - Optional integer timeout value (in milliseconds) or function that receives the assigns.

  ## Example

      @impl Backpex.LiveResource
      def fields do
        [
          created_at: %{
            module: Backpex.Fields.Time,
            label: "Deliver By",
            format: "%I:%M %p"
          }
        ]
      end
  """
  use BackpexWeb, :field

  @impl Backpex.Field
  def render_value(assigns) do
    format = Map.get(assigns.field_options, :format, @default_format)

    value =
      cond do
        is_function(format, 1) -> format.(assigns.value)
        assigns.value -> Calendar.strftime(assigns.value, format)
        true -> HTML.pretty_value(assigns.value)
      end

    assigns =
      assigns
      |> assign(:value, value)

    ~H"""
    <p class={@live_action in [:index, :resource_action] && "truncate"}>
      <%= @value %>
    </p>
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
          type="time"
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
        <:label align={Backpex.Field.align_label(@field_options, assigns, :top)}>
          <Layout.input_label text={@field_options[:label]} />
        </:label>
        <BackpexForm.input
          type="time"
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
      |> assign(:valid, Map.get(assigns, :valid, true))
      |> assign_new(:form, fn -> form end)

    ~H"""
    <div>
      <.form for={@form} phx-change="update-field" phx-submit="update-field" phx-target={@myself}>
        <BackpexForm.input
          type="time"
          field={@form[:value]}
          input_class={["input input-sm w-32", @valid && "hover:input-bordered", !@valid && "input-error"]}
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
