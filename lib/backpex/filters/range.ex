defmodule Backpex.Filters.Range do
  @moduledoc """
  The range filter renders two input fields of the same type. Backpex offers the `:date`, `:datetime` and the `number` type.

  See the following example for an implementation of a date range filter.

      defmodule MyAppWeb.Filters.DateRange do
        use Backpex.Filters.Range

        @impl Backpex.Filters.Range
        def type, do: :date

        @impl Backpex.Filter
        def label, do: "Date Range (begins at)"
      end

  > #### Information {: .info}
  >
  > Note that the query function is already implemented via `Backpex.Filters.Range`.

  > #### `use Backpex.Filters.Range` {: .info}
  >
  > When you `use Backpex.Filters.Range`, the `Backpex.Filters.Range` module will set `@behavior Backpex.Filters.Range`.
  > In addition it will add a `render` and `render_form` function in order to display the corresponding filter.
  > It will also implement the `Backpex.Filter.query` function to define a range query.
  """
  use BackpexWeb, :filter

  require Backpex

  @doc """
  The type return value defines the rendered input fields of the range filter.
  """
  @callback type :: :date | :datetime | :number

  defmacro __using__(_opts) do
    quote do
      use BackpexWeb, :filter
      use Backpex.Filter

      alias Backpex.Filters.Range, as: RangeFilter

      @behaviour RangeFilter

      @impl Backpex.Filter
      def query(query, attribute, params, assigns) do
        RangeFilter.query(query, type(), attribute, params, assigns)
      end

      @impl Backpex.Filter
      def render(assigns) do
        RangeFilter.render(assigns)
      end

      @impl Backpex.Filter
      def render_form(assigns) do
        type = RangeFilter.render_type(type())
        assigns = assign(assigns, :type, type)
        Backpex.Filters.Range.render_form(assigns)
      end

      defoverridable query: 4, render: 1, render_form: 1
    end
  end

  attr :value, :map, required: true

  def render(assigns) do
    assigns =
      assigns
      |> assign(:min, assigns.value["start"])
      |> assign(:max, assigns.value["end"])

    ~H"""
    <span :if={@max == ""}>&gt; {@min}</span>
    <span :if={@min == ""}>&lt; {@max}</span>
    <span :if={@min != "" and @max != ""}>{@min} &mdash; {@max}</span>
    """
  end

  attr :form, :any, required: true
  attr :field, :atom, required: true
  attr :value, :any, required: true
  attr :type, :atom, required: true
  attr :live_resource, :atom, required: true

  def render_form(assigns) do
    ~H"""
    <.inputs_for :let={f} field={@form[@field]}>
      <.range_input_set form={f} type={@type} value={@value} live_resource={@live_resource} />
    </.inputs_for>
    """
  end

  attr :form, :any, required: true
  attr :type, :atom, required: true
  attr :value, :any, required: true
  attr :live_resource, :atom, required: true

  def range_input_set(%{type: :date} = assigns) do
    ~H"""
    <div class="mt-2">
      <label class="input input-sm mb-2">
        <span class="text-base-content/50 w-10">{Backpex.__("From", @live_resource)}</span>
        <input type="date" name={@form[:start].name} value={@value["start"]} class="inline-block" />
      </label>
      <label class="input input-sm">
        <span class="text-base-content/50 w-10">{Backpex.__("To", @live_resource)}</span>
        <input type="date" name={@form[:end].name} value={@value["end"]} class="inline-block" />
      </label>
    </div>
    """
  end

  def range_input_set(%{type: :number} = assigns) do
    ~H"""
    <div class="mt-2">
      <label class="input input-sm mb-2">
        <span class="text-base-content/50 w-10">{Backpex.__("From", @live_resource)}</span>
        <input type="number" name={@form[:start].name} value={@value["start"]} />
      </label>
      <label class="input input-sm">
        <span class="text-base-content/50 w-10">{Backpex.__("To", @live_resource)}</span>
        <input type="number" name={@form[:end].name} value={@value["end"]} />
      </label>
    </div>
    """
  end

  def query(query, type, attribute, %{"start" => start_at, "end" => end_at}, _assigns) do
    maybe_parse_range(type, start_at, end_at)
    |> do_query(query, attribute)
  end

  def query(query, _type, _attribute, _params, _assigns) do
    query
  end

  def do_query({nil, nil}, query, _attribute), do: query

  def do_query({start_at, nil}, query, attribute) do
    where(query, [x], field(x, ^attribute) >= ^start_at)
  end

  def do_query({nil, end_at}, query, attribute) do
    where(query, [x], field(x, ^attribute) <= ^end_at)
  end

  def do_query({start_at, end_at}, query, attribute) do
    where(query, [x], field(x, ^attribute) >= ^start_at and field(x, ^attribute) <= ^end_at)
  end

  @doc """
  Parses both start and end values for a range filter.

  ## Examples

      iex> Backpex.Filters.Range.maybe_parse_range(:number, "10", "100")
      {10, 100}

      iex> Backpex.Filters.Range.maybe_parse_range(:number, "", "100")
      {nil, 100}

      iex> Backpex.Filters.Range.maybe_parse_range(:number, "10", "")
      {10, nil}

      iex> Backpex.Filters.Range.maybe_parse_range(:date, "2024-01-01", "2024-12-31")
      {"2024-01-01", "2024-12-31"}

      iex> Backpex.Filters.Range.maybe_parse_range(:datetime, "2024-01-01", "2024-12-31")
      {"2024-01-01T00:00:00+00:00", "2024-12-31T23:59:59+00:00"}

  """
  def maybe_parse_range(type, start_at, end_at) do
    {maybe_parse(type, start_at), maybe_parse(type, end_at, true)}
  end

  @doc """
  Parses a single value based on the specified type.

  The third parameter `is_end?` determines whether to treat the value as an end boundary
  (which affects datetime parsing by adding 23:59:59 instead of 00:00:00).

  ## Examples

      iex> Backpex.Filters.Range.maybe_parse(:number, "")
      nil

      iex> Backpex.Filters.Range.maybe_parse(:date, "")
      nil

      iex> Backpex.Filters.Range.maybe_parse(:datetime, "")
      nil

      iex> Backpex.Filters.Range.maybe_parse(:date, "2024-06-15")
      "2024-06-15"

      iex> Backpex.Filters.Range.maybe_parse(:date, "not-a-date")
      nil

      iex> Backpex.Filters.Range.maybe_parse(:date, "2024-13-45")
      nil

      iex> Backpex.Filters.Range.maybe_parse(:datetime, "2024-01-01", false)
      "2024-01-01T00:00:00+00:00"

      iex> Backpex.Filters.Range.maybe_parse(:datetime, "2024-12-31", true)
      "2024-12-31T23:59:59+00:00"

      iex> Backpex.Filters.Range.maybe_parse(:datetime, "invalid")
      nil

  """
  def maybe_parse(type, value, is_end? \\ false)

  def maybe_parse(_type, "", _is_end?), do: nil

  def maybe_parse(:date, value, _is_end?) do
    if date?(value), do: value
  end

  def maybe_parse(:datetime, value, false = _is_end?) do
    if date?(value), do: value <> "T00:00:00+00:00"
  end

  def maybe_parse(:datetime, value, _is_end?) do
    if date?(value), do: value <> "T23:59:59+00:00"
  end

  def maybe_parse(:number, value, _is_end?), do: parse_float_or_int(value)

  @doc """
  Parses a string value as either an integer or float.

  Prefers integer representation for whole numbers.

  ## Examples

      iex> Backpex.Filters.Range.parse_float_or_int("42")
      42

      iex> Backpex.Filters.Range.parse_float_or_int("-10")
      -10

      iex> Backpex.Filters.Range.parse_float_or_int("0")
      0

      iex> Backpex.Filters.Range.parse_float_or_int("3.14")
      3.14

      iex> Backpex.Filters.Range.parse_float_or_int("-2.5")
      -2.5

      iex> Backpex.Filters.Range.parse_float_or_int("0.0")
      0.0

      iex> Backpex.Filters.Range.parse_float_or_int("not-a-number")
      nil

      iex> Backpex.Filters.Range.parse_float_or_int("abc123")
      nil

      iex> Backpex.Filters.Range.parse_float_or_int("12abc")
      nil

      iex> Backpex.Filters.Range.parse_float_or_int("")
      nil

  """
  def parse_float_or_int(value) do
    case {Integer.parse(value), Float.parse(value)} do
      {{value, ""}, _parsed_float} -> value
      {_parsed_integer, {value, ""}} -> value
      {_parsed_integer_err, _parsed_float_err} -> nil
    end
  end

  @doc """
  Checks if a string is a valid ISO 8601 date.

  ## Examples

      iex> Backpex.Filters.Range.date?("2024-01-01")
      true

      iex> Backpex.Filters.Range.date?("2023-12-31")
      true

      iex> Backpex.Filters.Range.date?("2000-06-15")
      true

      iex> Backpex.Filters.Range.date?("not-a-date")
      false

      iex> Backpex.Filters.Range.date?("2024-13-01")
      false

      iex> Backpex.Filters.Range.date?("2024-01-32")
      false

      iex> Backpex.Filters.Range.date?("")
      false

  """
  def date?(date) do
    case Date.from_iso8601(date) do
      {:ok, _date} -> true
      _err -> false
    end
  end

  @doc """
  Returns the render type for form inputs.

  Converts `:datetime` to `:date` since HTML date inputs are used for datetime filters.

  ## Examples

      iex> Backpex.Filters.Range.render_type(:datetime)
      :date

      iex> Backpex.Filters.Range.render_type(:date)
      :date

      iex> Backpex.Filters.Range.render_type(:number)
      :number

  """
  def render_type(:datetime = _type), do: :date
  def render_type(type), do: type
end
