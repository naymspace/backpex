defmodule Backpex.Filters.Select do
  @moduledoc """
  Tbe select filter renders a select box for the implemented `options/0` and `prompt/0` callbacks. The `prompt/0` callback defines the key for the `nil` value added as first option.

  See the following example for an implementation of an event status filter.

      defmodule MyAppWeb.Filters.EventStatusSelect do
        use Backpex.Filters.Select

        @impl Backpex.Filter
        def label, do: "Event status"

        @impl Backpex.Filters.Select
        def prompt, do: "Select an option..."

        @impl Backpex.Filters.Select
        def options, do: [
          {"Open", :open},
          {"Close", :close},
        ]

        @impl Backpex.Filter
        def query(query, attribute, value) do
            where(query, [x], field(x, ^attribute) == ^value)
        end
      end

  > #### `use Backpex.Filters.Select` {: .info}
  >
  > When you `use Backpex.Filters.Select`, the `Backpex.Filters.Select` module will set `@behavior Backpex.Filters.Select`.
  > In addition it will add a `render` and `render_form` function in order to display the corresponding filter.
  """
  use BackpexWeb, :filter

  @doc """
  The select's default option.
  """
  @callback prompt :: String.t() | atom()

  @doc """
  The list of options for the select filter.
  """
  @callback options :: [{String.t() | atom(), String.t() | atom()}]

  defmacro __using__(_opts) do
    quote do
      use BackpexWeb, :filter
      use Backpex.Filter

      alias Backpex.Filters.Select, as: SelectFilter

      @behaviour Backpex.Filters.Select

      @impl Backpex.Filter
      defdelegate query(query, attribute, value), to: SelectFilter

      @impl Backpex.Filter
      def render(assigns) do
        assigns = assign(assigns, :options, options())
        SelectFilter.render(assigns)
      end

      @impl Backpex.Filter
      def render_form(assigns) do
        assigns =
          assigns
          |> assign(:options, options())
          |> assign(:prompt, prompt())

        SelectFilter.render_form(assigns)
      end

      defoverridable query: 3, render: 1, render_form: 1
    end
  end

  attr :value, :any, required: true
  attr :options, :list, required: true

  def render(assigns) do
    assigns = assign(assigns, :label, option_value_to_label(assigns.options, assigns.value))

    ~H"""
    {@label}
    """
  end

  attr :form, :any, required: true
  attr :field, :atom, required: true
  attr :value, :any, required: true
  attr :options, :list, required: true
  attr :prompt, :string, required: true

  def render_form(assigns) do
    ~H"""
    <select name={@form[@field].name} class="select select-sm mt-2">
      <option value="">{@prompt}</option>
      {Phoenix.HTML.Form.options_for_select(@options, selected(@value))}
    </select>
    """
  end

  def selected(""), do: nil
  def selected(value), do: value

  def query(query, attribute, value) do
    where(query, [x], field(x, ^attribute) == ^value)
  end

  def option_value_to_label(options, value) do
    Enum.find_value(options, fn {option_label, option_value} ->
      if to_string(option_value) == to_string(value), do: option_label
    end)
  end
end
