# credo:disable-for-this-file Credo.Check.Design.DuplicatedCode
defmodule Backpex.Fields.DateTime do
  @default_format "%Y-%m-%d %I:%M %p"

  # credo:disable-for-next-line Credo.Check.Readability.StrictModuleLayout
  @moduledoc """
  A field for handling a date time value.

  ## Options

    * `:format` - Format string which will be used to format the date time value.
      Defaults to `#{@default_format}`
    * `:debounce` - Optional integer timeout value (in milliseconds), or "blur".
    * `:throttle` - Optional integer timeout value (in milliseconds).

  ## Example

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
  """
  use BackpexWeb, :field

  @impl Backpex.Field
  def render_value(assigns) do
    format = Map.get(assigns.field_options, :format, @default_format)

    value =
      if assigns.value,
        do: Calendar.strftime(assigns.value, format),
        else: HTML.pretty_value(assigns.value)

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
end
