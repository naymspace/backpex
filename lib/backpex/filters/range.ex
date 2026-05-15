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
      @behaviour Backpex.Filters.Range

      use BackpexWeb, :filter
      use Backpex.Filter

      alias Backpex.Filters.Range, as: RangeFilter

      @impl Backpex.Filter
      def type(_assigns), do: :map

      @impl Backpex.Filter
      def changeset(changeset, field, _assigns) do
        RangeFilter.changeset(changeset, field, type())
      end

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

      defoverridable type: 1, changeset: 3, query: 4, render: 1, render_form: 1
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
  attr :errors, :list, default: []

  def render_form(assigns) do
    ~H"""
    <.inputs_for :let={f} field={@form[@field]}>
      <.range_input_set form={f} type={@type} value={@value} live_resource={@live_resource} errors={@errors} />
    </.inputs_for>
    <.error :for={msg <- @errors} class="mt-1">{msg}</.error>
    """
  end

  attr :form, :any, required: true
  attr :type, :atom, required: true
  attr :value, :any, required: true
  attr :live_resource, :atom, required: true
  attr :errors, :list, default: []

  def range_input_set(%{type: :date} = assigns) do
    ~H"""
    <div class="mt-2">
      <label class={["input input-sm mb-2", @errors != [] && "input-error bg-error/10"]}>
        <span class="text-base-content/50 w-10">{Backpex.__("From", @live_resource)}</span>
        <input type="date" name={@form[:start].name} value={@value["start"]} class="inline-block" />
      </label>
      <label class={["input input-sm", @errors != [] && "input-error bg-error/10"]}>
        <span class="text-base-content/50 w-10">{Backpex.__("To", @live_resource)}</span>
        <input type="date" name={@form[:end].name} value={@value["end"]} class="inline-block" />
      </label>
    </div>
    """
  end

  def range_input_set(%{type: :number} = assigns) do
    ~H"""
    <div class="mt-2">
      <label class={["input input-sm mb-2", @errors != [] && "input-error bg-error/10"]}>
        <span class="text-base-content/50 w-10">{Backpex.__("From", @live_resource)}</span>
        <input type="number" name={@form[:start].name} value={@value["start"]} />
      </label>
      <label class={["input input-sm", @errors != [] && "input-error bg-error/10"]}>
        <span class="text-base-content/50 w-10">{Backpex.__("To", @live_resource)}</span>
        <input type="number" name={@form[:end].name} value={@value["end"]} />
      </label>
    </div>
    """
  end

  @doc """
  Validates range filter values based on the filter type.

  Validates that:
  - Date values are valid ISO 8601 dates (for :date and :datetime types)
  - Number values are valid integers or floats (for :number type)
  - Start is not greater than end when both are provided
  """
  def changeset(changeset, field, range_type) do
    Ecto.Changeset.validate_change(changeset, field, fn _field, value ->
      validate_range(value, range_type, field)
    end)
  end

  defp validate_range(nil, _type, _field), do: []
  defp validate_range(%{"start" => "", "end" => ""}, _type, _field), do: []
  defp validate_range(%{"start" => nil, "end" => nil}, _type, _field), do: []

  defp validate_range(%{"start" => start_val, "end" => end_val}, type, field) do
    start_parsed = maybe_parse(type, start_val || "")
    end_parsed = maybe_parse(type, end_val || "", true)

    []
    |> validate_start_format(start_val, start_parsed, field)
    |> validate_end_format(end_val, end_parsed, field)
    |> validate_start_not_after_end(start_parsed, end_parsed, type, field)
  end

  defp validate_range(_value, _type, _field), do: []

  defp validate_start_format(errors, start_val, start_parsed, field) do
    if start_val not in ["", nil] and is_nil(start_parsed) do
      [{field, "has invalid start value"} | errors]
    else
      errors
    end
  end

  defp validate_end_format(errors, end_val, end_parsed, field) do
    if end_val not in ["", nil] and is_nil(end_parsed) do
      [{field, "has invalid end value"} | errors]
    else
      errors
    end
  end

  defp validate_start_not_after_end(errors, nil, _end_parsed, _type, _field), do: errors
  defp validate_start_not_after_end(errors, _start_parsed, nil, _type, _field), do: errors

  defp validate_start_not_after_end(errors, start_parsed, end_parsed, type, field) do
    case compare_values(type, start_parsed, end_parsed) do
      :gt -> [{field, "start must be less than or equal to end"} | errors]
      :error -> [{field, "has invalid date format"} | errors]
      _other -> errors
    end
  end

  defp compare_values(:number, start_val, end_val) when start_val > end_val, do: :gt
  defp compare_values(:number, _start_val, _end_val), do: :lte

  defp compare_values(:date, start_val, end_val) do
    with {:ok, start_date} <- Date.from_iso8601(start_val),
         {:ok, end_date} <- Date.from_iso8601(end_val) do
      case Date.compare(start_date, end_date) do
        :gt -> :gt
        _other -> :lte
      end
    else
      {:error, _reason} -> :error
    end
  end

  defp compare_values(:datetime, start_val, end_val) do
    # Extract date portion from datetime strings for comparison
    start_date = String.slice(start_val, 0, 10)
    end_date = String.slice(end_val, 0, 10)
    compare_values(:date, start_date, end_date)
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
  def maybe_parse(_type, nil, _is_end?), do: nil

  def maybe_parse(:date, %Date{} = value, _is_end?), do: Date.to_iso8601(value)

  def maybe_parse(:date, value, _is_end?) do
    if date?(value), do: value
  end

  def maybe_parse(:datetime, %Date{} = value, false = _is_end?),
    do: Date.to_iso8601(value) <> "T00:00:00+00:00"

  def maybe_parse(:datetime, %Date{} = value, _is_end?),
    do: Date.to_iso8601(value) <> "T23:59:59+00:00"

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
  def parse_float_or_int(value) when is_integer(value), do: value
  def parse_float_or_int(value) when is_float(value), do: value

  def parse_float_or_int(value) when is_binary(value) do
    case {Integer.parse(value), Float.parse(value)} do
      {{value, ""}, _parsed_float} -> value
      {_parsed_integer, {value, ""}} -> value
      {_parsed_integer_err, _parsed_float_err} -> nil
    end
  end

  def parse_float_or_int(_other), do: nil

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
  def date?(date) when is_binary(date) do
    case Date.from_iso8601(date) do
      {:ok, _date} -> true
      _err -> false
    end
  end

  def date?(_other), do: false

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
