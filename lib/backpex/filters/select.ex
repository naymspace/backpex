defmodule Backpex.Filters.Select do
  @moduledoc """
  The select filter behaviour. Renders a select box for the implemented `options/0` and `prompt/0` callbacks.
  `prompt/0` defines the key for the `nil` value added as first option.

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
  use Phoenix.Component, global_prefixes: ~w(x-)
  import Ecto.Query, warn: false

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

      alias Backpex.Filters.Select, as: SelectFilter

      @behaviour Backpex.Filters.Select

      @impl Backpex.Filter
      defdelegate query(query, attribute, value), to: SelectFilter

      @impl Backpex.Filter
      def render(var!(assigns)) do
        var!(assigns) = assign(var!(assigns), :options, options())

        ~H"""
        <SelectFilter.render options={@options} value={@value} />
        """
      end

      @impl Backpex.Filter
      def render_form(var!(assigns) = assigns) do
        var!(assigns) = assign(var!(assigns), :options, options())

        ~H"""
        <SelectFilter.render_form form={@form} field={@field} value={@value} options={@options} prompt={@prompt} />
        """
      end

      defoverridable query: 3, render: 1, render_form: 1
    end
  end

  attr :value, :any, required: true
  attr :options, :list, required: true

  def render(assigns) do
    assigns = assign(assigns, :label, option_value_to_label(assigns.options, assigns.value))

    ~H"""
    <%= @label %>
    """
  end

  attr :form, :any, required: true
  attr :field, :atom, required: true
  attr :value, :any, required: true
  attr :options, :list, required: true
  attr :prompt, :string, required: true

  def render_form(assigns) do
    assigns =
      assigns
      |> assign(:options, [{assigns.prompt, nil} | assigns.options])
      |> assign(:selected, selected(assigns.value))

    ~H"""
    <%= Phoenix.HTML.Form.select(
      @form,
      @field,
      @options,
      class: "select select-sm select-bordered mt-2 w-full",
      selected: @selected
    ) %>
    """
  end

  def selected(""), do: nil
  def selected(value), do: value

  def query(query, attribute, value) do
    where(query, [x], field(x, ^attribute) == ^value)
  end

  def option_value_to_label(options, value) do
    Enum.find_value(options, fn {option_label, option_value} ->
      if option_value == value, do: option_label
    end)
  end
end
