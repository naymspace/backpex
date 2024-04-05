defmodule Backpex.Fields.Select do
  @moduledoc """
  A field for handling a select value.

  ## Options

    * `:options` - Required (keyword) list of options or function that receives the assigns.
    * `:prompt` - The text to be displayed when no option is selected.

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
    label = get_label(assigns, options)

    assigns = assign(assigns, :label, label)

    ~H"""
    <p class={@live_action in [:index, :resource_action] && "truncate"}>
      <%= HTML.pretty_value(@label) %>
    </p>
    """
  end

  @impl Backpex.Field
  def render_form(assigns) do
    options = Map.get(assigns.field_options, :options)

    assigns =
      assigns
      |> assign_options(options)
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

  @impl Backpex.Field
  def render_index_form(assigns) do
    form = to_form(%{"value" => assigns.value}, as: :index_form)
    options = Map.get(assigns.field_options, :options)

    assigns =
      assigns
      |> assign(:form, form)
      |> assign_options(options)
      |> assign_new(:valid, fn -> true end)
      |> assign_prompt(assigns.field_options)

    ~H"""
    <div>
      <.form for={@form} class="relative" phx-change="update-field" phx-submit="update-field" phx-target={@myself}>
        <select
          name={@form[:value].name}
          class={["select select-sm", if(@valid, do: "hover:input-bordered", else: "select-error")]}
          disabled={@readonly}
        >
          <option :if={@prompt} value=""><%= Map.get(@prompt, :prompt) %></option>
          <%= Phoenix.HTML.Form.options_for_select(@options, @value) %>
        </select>
      </.form>
    </div>
    """
  end

  @impl Phoenix.LiveComponent
  def handle_event("update-field", %{"index_form" => %{"value" => value}}, socket) do
    Backpex.Field.handle_index_editable(socket, %{} |> Map.put(socket.assigns.name, value))
  end

  defp get_label(assigns, options) when is_function(options), do: get_label(assigns, options.(assigns))

  defp get_label(%{value: value} = _assigns, options) do
    case Enum.find(options, fn option -> value?(option, value) end) do
      nil -> value
      {label, _value} -> label
      label -> label
    end
  end

  defp value?({_label, value}, to_compare), do: to_string(value) == to_string(to_compare)
  defp value?(value, to_compare), do: to_string(value) == to_string(to_compare)

  defp assign_prompt(assigns, %{prompt: prompt} = _field_options), do: assign(assigns, :prompt, %{prompt: prompt})
  defp assign_prompt(assigns, _field_options), do: assign(assigns, :prompt, %{})

  defp assign_options(assigns, options) when is_function(options), do: assign(assigns, :options, options.(assigns))
  defp assign_options(assigns, options), do: assign(assigns, :options, options)
end
