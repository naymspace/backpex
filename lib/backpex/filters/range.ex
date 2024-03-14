defmodule Backpex.Filters.Range do
  @moduledoc """
  Range filters render two input fields of the same type. Backpex offers the `:date`, `:datetime` and the `number` type.

  A basic implementation of a date range filter would look like this:

      defmodule MyAppWeb.Filters.DateRange do
        use Backpex.Filters.Range

        @impl Backpex.Filters.Range
        def type, do: :date

        @impl Backpex.Filter
        def label, do: "Date Range (begins at)"
      end

  > Note that the query function is already implemented via `Backpex.Filters.Range`.

  > #### `use Backpex.Filters.Range` {: .info}
  >
  > When you `use Backpex.Filters.Range`, the `Backpex.Filters.Range` module will set `@behavior Backpex.Filters.Range`.
  > In addition it will add a `render` and `render_form` function in order to display the corresponding filter.
  > It will also implement the `Backpex.Filter.query` function to define a range query.
  """

  @doc """
  The type return value defines the rendered input fields of the range filter.
  """
  @callback type :: :date | :datetime | :number

  defmacro __using__(_opts) do
    quote do
      use BackpexWeb, :filter

      @behaviour Backpex.Filters.Range

      @impl Backpex.Filter
      def query(query, attribute, %{"start" => start_at, "end" => end_at}) do
        maybe_parse_range(start_at, end_at)
        |> do_query(query, attribute)
      end

      @impl Backpex.Filter
      def query(query, attribute, _params) do
        query
      end

      defp do_query({nil, nil}, query, _attribute), do: query

      defp do_query({start_at, nil}, query, attribute) do
        where(query, [x], field(x, ^attribute) >= ^start_at)
      end

      defp do_query({nil, end_at}, query, attribute) do
        where(query, [x], field(x, ^attribute) <= ^end_at)
      end

      defp do_query({start_at, end_at}, query, attribute) do
        where(query, [x], field(x, ^attribute) >= ^start_at and field(x, ^attribute) <= ^end_at)
      end

      defp maybe_parse_range(start_at, end_at) do
        type = type()

        {maybe_parse(type, start_at), maybe_parse(type, end_at, true)}
      end

      defp maybe_parse(type, value, is_end? \\ false)

      defp maybe_parse(_type, "", _is_end?), do: nil

      defp maybe_parse(:date, value, _is_end?), do: if(date?(value), do: value, else: nil)

      defp maybe_parse(:datetime, value, false = _is_end?),
        do: if(date?(value), do: value <> "T00:00:00+00:00", else: nil)

      defp maybe_parse(:datetime, value, _is_end?), do: if(date?(value), do: value <> "T23:59:59+00:00", else: nil)

      defp maybe_parse(:number, value, _is_end?), do: parse_float_or_int(value)

      defp parse_float_or_int(value) do
        case {Integer.parse(value), Float.parse(value)} do
          {{value, ""}, _parsed_float} -> value
          {_parsed_integer, {value, ""}} -> value
          {_parsed_integer_err, _parsed_float_err} -> nil
        end
      end

      defp render_type do
        case type() do
          :datetime -> :date
          other -> other
        end
      end

      defp date?(date) do
        case Date.from_iso8601(date) do
          {:ok, _} -> true
          _err -> false
        end
      end

      @impl Backpex.Filter
      def render(var!(assigns)) do
        var!(assigns) =
          var!(assigns)
          |> assign(:min, var!(assigns).value["start"])
          |> assign(:max, var!(assigns).value["end"])

        ~H"""
        <span :if={@max == ""}>&gt; <%= @min %></span>
        <span :if={@min == ""}>&lt; <%= @max %></span>
        <span :if={@min != "" and @max != ""}><%= @min %> &mdash; <%= @max %></span>
        """
      end

      @impl Backpex.Filter
      def render_form(var!(assigns) = assigns) do
        ~H"""
        <.inputs_for :let={f} field={@form[@field]}>
          <.range_input_set form={f} type={render_type()} value={@value} />
        </.inputs_for>
        """
      end

      defp range_input_set(%{type: :date} = var!(assigns)) do
        ~H"""
        <div class="mt-2">
          <%= Phoenix.HTML.Form.date_input(
            @form,
            "start",
            value: @value["start"],
            class: "input input-sm input-bordered mb-2 w-full"
          ) %>
          <%= Phoenix.HTML.Form.date_input(
            @form,
            "end",
            value: @value["end"],
            class: "input input-sm input-bordered w-full"
          ) %>
        </div>
        """
      end

      defp range_input_set(%{type: :number} = var!(assigns)) do
        ~H"""
        <div class="mt-2">
          <%= Phoenix.HTML.Form.number_input(
            @form,
            "start",
            value: @value["start"],
            class: "input input-sm input-bordered mb-2 w-full"
          ) %>
          <%= Phoenix.HTML.Form.number_input(
            @form,
            "end",
            value: @value["end"],
            class: "input input-sm input-bordered w-full"
          ) %>
        </div>
        """
      end

      defoverridable query: 3
    end
  end
end
