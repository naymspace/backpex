# Custom Filter

Backpex ships with a set of default filters that can be used to filter the data. In addition to the default filters, you can create custom filters for more advanced use cases.

## Creating a Custom Filter

You can create a custom filter by using the `filter` macro from the `BackpexWeb` module.. It automatically implements the `Backpex.Filter` behavior and defines some aliases and imports.

When creating a custom filter, you need to implement the following callbacks: `query/3`, `render/1` and `render_form/1`. The `query/3` function is used to filter the data based on the filter values. It receives the query, the attribute and the values of the filter and should return the filtered query. The `render/1` function returns the markup that is used to display the filter on the index view. The `render_form/1` function returns the markup that is used to render the filter form on the index view.

Here is an example of a custom select filter:

```elixir
defmodule MyApp.Filters.CustomSelectFilter do
    use BackpexWeb, :filter

    @impl Backpex.Filter
    def label, do: "Event status"

    @impl Backpex.Filter
    def render(assigns) do
        assigns = assign(assigns, :label, option_value_to_label(options(), assigns.value))

        ~H"""
        <%= @label %>
        """
    end

    @impl Backpex.Filter
    def render_form(assigns) do
        ~H"""
        <.form_field
            type="select"
            selected={selected(@value)}
            options={my_options()}
            form={@form}
            field={@field}
            label=""
        />
        """
    end

    @impl Backpex.Filter
    def query(query, attribute, value, _assigns) do
        where(query, [x], field(x, ^attribute) == ^value)
    end

    defp option_value_to_label(options, value) do
        Enum.find_value(options, fn {option_label, option_value} ->
        if option_value == value, do: option_label
        end)
    end

    defp my_options, do: [
        {"Select an option...", nil},
        {"Open", :open},
        {"Close", :close},
    ]

    defp selected(""), do: nil
    defp selected(value), do: value
end
```

In this example, we define a custom select filter that filters the data based on the event status. The `query/3` function filters the data based on the selected value.

See `Backpex.Filter` for available callback functions.
