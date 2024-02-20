defmodule Backpex.Fields.Select do
  @moduledoc """
  A field for handling a select value.

  ## Options

    * `:options` - Required (keyword) list of options to be used for the select.
    * `:prompt` - The text to be displayed when no option is selected.
      Allows the same values as [`Phoenix.Html.Form.select`](https://hexdocs.pm/phoenix_html/Phoenix.HTML.Form.html#select/4) for customization of the prompt.

  ## Example

      @impl Backpex.LiveResource
      def fields do
        [
          role: %{
            module: Backpex.Fields.Select,
            label: "Role",
            options: [Admin: admin, User: user]
          }
        ]
      end
  """
  use BackpexWeb, :field

  @impl Backpex.Field
  def render_value(assigns) do
    options = Map.get(assigns.field_options, :options)

    label =
      assigns.value
      |> Atom.to_string()
      |> get_label(options)

    assigns =
      assigns
      |> assign(:label, label)

    ~H"""
    <p class={@live_action in [:index, :resource_action] && "truncate"}>
      <%= @label %>
    </p>
    """
  end

  @impl Backpex.Field
  def render_form(assigns) do
    options = Map.get(assigns.field_options, :options)

    assigns =
      assigns
      |> assign(:options, options)
      |> assign_prompt(assigns.field_options)

    ~H"""
    <div>
      <Layout.field_container>
        <:label align={Backpex.Field.align_label(@field_options, assigns)}>
          <Layout.input_label text={@field_options[:label]} />
        </:label>
        <BackpexForm.field_input
          type="select"
          field={@form[@name]}
          field_options={@field_options}
          options={@options}
          {@prompt}
        />
      </Layout.field_container>
    </div>
    """
  end

  defp get_label(value, options) do
    case Enum.find(options, fn option -> value?(option, value) end) do
      nil -> value
      {label, _value} -> label
      label -> label
    end
  end

  defp value?({_label, value}, to_compare), do: value == to_compare
  defp value?(value, to_compare), do: value == to_compare

  defp assign_prompt(assigns, %{prompt: prompt} = _field_options), do: assign(assigns, :prompt, %{prompt: prompt})
  defp assign_prompt(assigns, _field_options), do: assign(assigns, :prompt, %{})
end
