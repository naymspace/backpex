defmodule Backpex.Filters.MultiSelect do
  @moduledoc """
  The multi select filter behaviour. Renders a multi select box for the implemented `options/0` callback.
  `prompt/0` defines the label for the multi select box.

  See the following example for an implementation of a multi select user filter.

      defmodule MyAppWeb.Filters.MultiUserSelect do
        use Backpex.Filters.MultiSelect

        @impl Backpex.Filter
        def label, do: "User"

        @impl Backpex.Filters.MultiSelect
        def prompt, do: "Select user ..."

        @impl Backpex.Filters.MultiSelect
        def options, do: [
          {"John Doe", "acdd1860-65ce-4ed6-a37c-433851cf68d7"},
          {"Jane Doe", "9d78ce5e-9334-4a6c-a076-f1e72522de2"}
        ]
      end

  > #### `use Backpex.Filters.MultiSelect` {: .info}
  >
  > When you `use Backpex.Filters.MultiSelect`, the `Backpex.Filters.MultiSelect` module will set `@behavior Backpex.Filters.Select`.
  > In addition it will add a `render` and `render_form` function in order to display the corresponding filter.
  """

  @doc """
  The list of options for the multi select filter.
  """
  @callback options :: [{String.t() | atom(), String.t() | atom()}]

  defmacro __using__(_opts) do
    quote do
      use BackpexWeb, :filter

      @behaviour Backpex.Filters.Select

      @impl Backpex.Filter
      def query(query, _attribute, []), do: query

      def query(query, attribute, value) do
        Enum.reduce(value, nil, fn
          v, nil ->
            dynamic([x], field(x, ^attribute) == ^v)

          v, p ->
            dynamic([x], ^p or field(x, ^attribute) == ^v)
        end)
        |> maybe_query(query)
      end

      defp maybe_query(nil, query), do: query
      defp maybe_query(predicates, query), do: where(query, ^predicates)

      @impl Backpex.Filter
      def render(var!(assigns)) do
        var!(assigns) =
          var!(assigns)
          |> assign(:label, option_value_to_label(options(), var!(assigns).value))

        ~H"""
        <%= @label %>
        """
      end

      defp option_value_to_label(options, values) do
        Enum.map(values, fn key -> find_option_label(options, key) end)
        |> Enum.intersperse(", ")
      end

      defp find_option_label(options, key) do
        Enum.find_value(options, fn {l, k} ->
          if k == key, do: l
        end) || ""
      end

      @impl Backpex.Filter
      def render_form(var!(assigns) = assigns) do
        value = if is_nil(assigns.value), do: [], else: assigns.value

        var!(assigns) =
          var!(assigns)
          |> assign(:value, value)
          |> assign(:options, options())
          |> assign(:prompt, prompt())

        ~H"""
        <div class="mt-2" x-data="{ open: false }">
          <div tabindex="0" @click="open = !open" role="button" class="select select-sm select-bordered w-full">
            <%= if @value == [] do %>
              <%= @prompt %>
            <% else %>
              <%= "#{Enum.count(@value)} #{Backpex.translate("selected")}" %>
            <% end %>
          </div>
          <ul
            tabindex="0"
            class="dropdown-content z-[1] menu bg-base-100 rounded-box min-w-60 max-h-96 w-max overflow-y-auto p-2 shadow"
            x-show="open"
            @click.outside="open = false"
          >
            <div class="space-y-2">
              <input type="hidden" name={@form[@field].name} value="" />
              <%= for {label, value} <- @options do %>
                <label class="flex cursor-pointer items-center gap-x-2">
                  <input
                    id={"#{@form[@field].name}[]-#{value}"}
                    type="checkbox"
                    name={@form[@field].name <> "[]"}
                    class="checkbox checkbox-sm checkbox-primary"
                    value={value}
                    checked={to_string(value) in @value}
                  />
                  <span class="label-text">
                    <%= label %>
                  </span>
                </label>
              <% end %>
            </div>
          </ul>
        </div>
        """
      end

      defoverridable query: 3
    end
  end
end
