defmodule Backpex.Filters.Boolean do
  @moduledoc """
  The Boolean Filter renders one checkbox per given option, hence multiple options can apply at the same time.
  Instead of implementing a `query` callback, you need to define predicates for each option leveraging [`Ecto.Query.dynamic/2`](https://hexdocs.pm/ecto/Ecto.Query.html#dynamic/2).

  > Please note that only query elements will work as a predicate that also work in an [`Ecto.Query.where/3`](https://hexdocs.pm/ecto/Ecto.Query.html#where/3).

  If none is selected, the filter does not change the query. If multiple options are selected they are logically reduced via `orWhere`.

  A really basic example is the following filter for a boolean column `:published`:

      defmodule MyAppWeb.Filters.EventPublished do
        use Backpex.Filters.Boolean

        @impl Backpex.Filter
        def label, do: "Published?"

        @impl Backpex.Filters.Boolean
        def options do
          [
            %{
              label: "Published",
              key: "published",
              predicate: dynamic([x], x.published)
            },
            %{
              label: "Not published",
              key: "not_published",
              predicate: dynamic([x], not x.published)
            }
          ]
        end
      end

  > #### `use Backpex.Filters.Boolean` {: .info}
  >
  > When you `use Backpex.Filters.Boolean`, the `Backpex.Filters.Boolean` module will set `@behavior Backpex.Filters.Boolean`.
  > In addition it will add a `render` and `render_form` function in order to display the corresponding filter.
  > It will also implement the `Backpex.Filter.query` function to define a boolean query.
  """

  @doc """
  The list of options for the select filter.
  """
  @callback options :: [map()]

  defmacro __using__(_opts) do
    quote do
      use BackpexWeb, :filter

      @behaviour Backpex.Filters.Boolean

      @impl Backpex.Filter
      def query(query, _attribute, []), do: query

      def query(query, attribute, value) do
        Enum.reduce(value, nil, fn
          v, nil ->
            Map.get(predicates(), v)

          v, p ->
            dynamic(^p or ^Map.get(predicates(), v))
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
        Enum.find_value(options, fn option ->
          if option.key == key, do: option.label
        end) || ""
      end

      @impl Backpex.Filter
      def render_form(var!(assigns) = assigns) do
        checked = if is_nil(assigns.value), do: [], else: assigns.value
        options = Enum.map(options(), fn %{label: l, key: k} -> {l, k} end)

        var!(assigns) =
          var!(assigns)
          |> assign(:checked, checked)
          |> assign(:options, options)

        ~H"""
        <div class="mt-2 flex flex-col space-y-2">
          <%= Phoenix.HTML.Form.hidden_input(@form, @field, name: Phoenix.HTML.Form.input_name(@form, @field), value: "") %>
          <%= for {label, key} <- @options do %>
            <label class="flex cursor-pointer items-center gap-x-2">
              <%= Phoenix.HTML.Form.checkbox(
                @form,
                @field,
                name: Phoenix.HTML.Form.input_name(@form, @field) <> "[]",
                class: "checkbox checkbox-sm checkbox-primary",
                checked: to_string(key) in @checked,
                checked_value: key,
                unchecked_value: "",
                hidden_input: false
              ) %>
              <span class="label-text">
                <%= label %>
              </span>
            </label>
          <% end %>
        </div>
        """
      end

      defp predicates do
        Enum.map(options(), fn %{predicate: p, key: k} -> {k, p} end)
        |> Enum.into(%{})
      end

      defoverridable query: 3
    end
  end
end
