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

      @behaviour Backpex.Filters.Select

      @impl Backpex.Filter
      def render(var!(assigns)) do
        var!(assigns) =
          var!(assigns)
          |> assign(:label, option_value_to_label(options(), var!(assigns).value))

        ~H"""
        <%= @label %>
        """
      end

      defp option_value_to_label(options, value) do
        Enum.find_value(options, fn {option_label, option_value} ->
          if option_value == value, do: option_label
        end)
      end

      @impl Backpex.Filter
      def render_form(var!(assigns) = assigns) do
        ~H"""
        <%= Phoenix.HTML.Form.select(
          @form,
          @field,
          [{prompt(), nil} | options()],
          class: "select select-sm select-bordered mt-2 w-full",
          selected: selected(@value)
        ) %>
        """
      end

      defp selected(""), do: nil
      defp selected(value), do: value
    end
  end
end
