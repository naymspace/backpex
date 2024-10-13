# credo:disable-for-this-file Credo.Check.Design.DuplicatedCode
defmodule Backpex.Fields.DateTime do
  @default_format "%Y-%m-%d %I:%M %p"

  # credo:disable-for-next-line Credo.Check.Readability.StrictModuleLayout
  @moduledoc """
  A field for handling a date time value.

  ## Options

    * `:format` - Format string which will be used to format the date time value or function that formats the date time.
      Defaults to `#{@default_format}`. If a function, must receive a `DateTime` and return a string.
    * `:debounce` - Optional integer timeout value (in milliseconds), "blur" or function that receives the assigns.
    * `:throttle` - Optional integer timeout value (in milliseconds) or function that receives the assigns.

  ## Examples

      @impl Backpex.LiveResource
      def fields do
        [
          created_at: %{
            module: Backpex.Fields.DateTime,
            label: "Created At",
            format: "%Y.%m.%d %I:%M %p" # optional
          }
        ]
      end

      @impl Backpex.LiveResource
      def fields do
        [
          created_at: %{
            module: Backpex.Fields.DateTime,
            label: "Created At",
            format: fn date_time -> # Takes a `DateTime` and returns a string
              # Timex should be installed separately, used as a reference for
              # custom formatting logic.
              Timex.format!(date_time, "{relative}", :relative)
            end
          }
        ]
      end

      @impl Backpex.LiveResource
      def fields do
        [
          created_at: %{
            module: Backpex.Fields.Date,
            label: "Created At",
            # If you use the same formatting logic in multiple places
            format: &MyApp.Formatters.Dates/1
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
        <BackpexForm.field_input
          type="datetime-local"
          field={@form[@name]}
          field_options={@field_options}
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
        <BackpexForm.field_input
          type="datetime-local"
          field={@form[@name]}
          field_options={@field_options}
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
        <input
          type="datetime-local"
          name={@form[:value].name}
          value={@form[:value].value}
          class={["input input-sm w-52", @valid && "hover:input-bordered", !@valid && "input-error"]}
          phx-debounce="100"
          readonly={@readonly}
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
