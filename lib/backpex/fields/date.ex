# credo:disable-for-this-file Credo.Check.Design.DuplicatedCode
defmodule Backpex.Fields.Date do
  @default_format "%Y-%m-%d"

  # credo:disable-for-next-line Credo.Check.Readability.StrictModuleLayout
  @moduledoc """
  A field for handling a date value.

  ## Options

    * `:format` - Defines the date format printed on the index view.
      Defaults to `#{@default_format}`.
    * `:debounce` - Optional integer timeout value (in milliseconds), or "blur".
    * `:throttle` - Optional integer timeout value (in milliseconds).

  ## Example

      @impl Backpex.LiveResource
      def fields do
        [
          created_at: %{
            module: Backpex.Fields.Date,
            label: "Created At",
            format: "%d.%m.%Y"
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
          type="date"
          form={@form}
          field_name={@name}
          field_options={@field_options}
          phx-debounce={Backpex.Field.debounce(@field_options, assigns)}
          phx-throttle={Backpex.Field.throttle(@field_options, assigns)}
        />
      </Layout.field_container>
    </div>
    """
  end
end
