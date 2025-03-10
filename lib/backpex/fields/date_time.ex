# credo:disable-for-this-file Credo.Check.Design.DuplicatedCode
defmodule Backpex.Fields.DateTime do
  @config_schema [
    format: [
      doc: """
      Format string which will be used to format the date time value or function that formats the date time.

      Can also be a function wich receives a `DateTime` and must return a string.
      """,
      type: {:or, [:string, {:fun, 1}]},
      default: "%Y-%m-%d %I:%M %p"
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
  A field for handling a date time value.

  ## Field-specific options

  See `Backpex.Field` for general field options.

  #{NimbleOptions.docs(@config_schema)}

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
  use Backpex.Field, config_schema: @config_schema

  @impl Backpex.Field
  def render_value(assigns) do
    format = assigns.field_options[:format]

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
      {@value}
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
          type="datetime-local"
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
          type="datetime-local"
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
          type="datetime-local"
          field={@form[:value]}
          input_class={["input input-sm w-52 [:not(:hover)]:input-ghost", !@valid && "input-error"]}
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
