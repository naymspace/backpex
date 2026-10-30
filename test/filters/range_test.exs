defmodule Backpex.Filters.RangeTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  alias Backpex.Filters.Range, as: RangeFilter

  doctest RangeFilter

  defmodule TestItem do
    use Ecto.Schema

    @primary_key {:id, :id, autogenerate: false}
    schema "items" do
      field :price, :decimal
      field :quantity, :integer
      field :created_at, :date
      field :updated_at, :utc_datetime
    end
  end

  defmodule TestLiveResource do
    def config(:adapter), do: Backpex.Adapters.Ecto
    def adapter_config(:schema), do: TestItem
  end

  defmodule QuantityRange do
    use Backpex.Filters.Range

    @impl Backpex.Filters.Range
    def type, do: :number

    @impl Backpex.Filter
    def label, do: "Quantity"
  end

  # Ecto casts query params while planning, so planning is enough to find values
  # that the database adapter would never receive.
  defmodule PlannerAdapter do
    def dumpers(_primitive, type), do: [type]
  end

  @assigns %{live_resource: TestLiveResource}

  defp plan(query), do: Ecto.Query.Planner.plan(query, :all, PlannerAdapter)

  defp number_changeset(field, value, assigns) do
    {%{}, %{field => :map}}
    |> Ecto.Changeset.cast(%{field => value}, [field])
    |> RangeFilter.changeset(field, :number, assigns)
  end

  describe "query/5 with :number type" do
    test "returns original query when both start and end are empty" do
      base_query = from(TestItem)

      query = RangeFilter.query(base_query, :number, :price, %{"start" => "", "end" => ""}, %{})

      assert query == base_query
    end

    test "applies >= condition when only start is provided" do
      base_query = from(TestItem)

      query = RangeFilter.query(base_query, :number, :price, %{"start" => "10", "end" => ""}, %{})

      assert [%{expr: where_expr}] = query.wheres
      assert match?({:>=, _, _}, where_expr)
    end

    test "applies <= condition when only end is provided" do
      base_query = from(TestItem)

      query = RangeFilter.query(base_query, :number, :price, %{"start" => "", "end" => "100"}, %{})

      assert [%{expr: where_expr}] = query.wheres
      assert match?({:<=, _, _}, where_expr)
    end

    test "applies between condition when both start and end are provided" do
      base_query = from(TestItem)

      query = RangeFilter.query(base_query, :number, :price, %{"start" => "10", "end" => "100"}, %{})

      assert [%{expr: where_expr}] = query.wheres
      # Should be an AND of >= and <=
      assert match?({:and, _, _}, where_expr)
    end
  end

  describe "query/5 with :number type on an integer field" do
    test "does not pass decimal values to the query" do
      base_query = from(TestItem)

      for value <- ["1.5", "5.0", "1e2"] do
        query = RangeFilter.query(base_query, :number, :quantity, %{"start" => value, "end" => "10"}, @assigns)

        assert [%{expr: where_expr, params: [{10, _type}]}] = query.wheres
        assert match?({:<=, _, _}, where_expr)
        assert {%Ecto.Query{}, _params, _key} = plan(query)
      end
    end

    test "passes integer values to the query" do
      base_query = from(TestItem)

      query = RangeFilter.query(base_query, :number, :quantity, %{"start" => "2", "end" => "10"}, @assigns)

      assert [%{params: [{2, _start_type}, {10, _end_type}]}] = query.wheres
      assert {%Ecto.Query{}, _params, _key} = plan(query)
    end
  end

  describe "filter validation and query on an integer field" do
    test "a decimal value is invalid and not applied to the query" do
      filter_configs = [quantity: %{module: QuantityRange}]
      params = %{"quantity" => %{"start" => "1.5", "end" => ""}}

      changeset = Backpex.FilterValidation.build_changeset(params, filter_configs, @assigns)
      filter_values = Backpex.FilterValidation.valid_values(changeset)
      base_query = from(TestItem)

      query = Backpex.Adapters.Ecto.apply_filters(base_query, filter_values, filter_configs, @assigns)

      assert changeset.errors == [quantity: {"has invalid start value", []}]
      assert filter_values == %{}
      assert query.wheres == []
      assert {%Ecto.Query{}, _params, _key} = plan(query)
    end
  end

  describe "query/5 with :date type" do
    test "returns original query when both start and end are empty" do
      base_query = from(TestItem)

      query = RangeFilter.query(base_query, :date, :created_at, %{"start" => "", "end" => ""}, %{})

      assert query == base_query
    end

    test "applies >= condition for valid start date" do
      base_query = from(TestItem)

      query =
        RangeFilter.query(base_query, :date, :created_at, %{"start" => "2024-01-01", "end" => ""}, %{})

      assert [%{expr: where_expr}] = query.wheres
      assert match?({:>=, _, _}, where_expr)
    end

    test "applies <= condition for valid end date" do
      base_query = from(TestItem)

      query =
        RangeFilter.query(base_query, :date, :created_at, %{"start" => "", "end" => "2024-12-31"}, %{})

      assert [%{expr: where_expr}] = query.wheres
      assert match?({:<=, _, _}, where_expr)
    end

    test "returns original query for invalid date format" do
      base_query = from(TestItem)

      query =
        RangeFilter.query(
          base_query,
          :date,
          :created_at,
          %{"start" => "not-a-date", "end" => "also-not-a-date"},
          %{}
        )

      assert query == base_query
    end
  end

  describe "query/5 with :datetime type" do
    test "returns original query when both start and end are empty" do
      base_query = from(TestItem)

      query =
        RangeFilter.query(base_query, :datetime, :updated_at, %{"start" => "", "end" => ""}, %{})

      assert query == base_query
    end

    test "applies >= condition with T00:00:00 for start date" do
      base_query = from(TestItem)

      query =
        RangeFilter.query(
          base_query,
          :datetime,
          :updated_at,
          %{"start" => "2024-01-01", "end" => ""},
          %{}
        )

      assert [%{expr: where_expr, params: params}] = query.wheres
      assert match?({:>=, _, _}, where_expr)

      # The datetime should have T00:00:00+00:00 appended
      assert Enum.any?(params, fn {val, _type} ->
               String.contains?(to_string(val), "T00:00:00")
             end)
    end

    test "applies <= condition with T23:59:59 for end date" do
      base_query = from(TestItem)

      query =
        RangeFilter.query(
          base_query,
          :datetime,
          :updated_at,
          %{"start" => "", "end" => "2024-12-31"},
          %{}
        )

      assert [%{expr: where_expr, params: params}] = query.wheres
      assert match?({:<=, _, _}, where_expr)

      # The datetime should have T23:59:59+00:00 appended
      assert Enum.any?(params, fn {val, _type} ->
               String.contains?(to_string(val), "T23:59:59")
             end)
    end
  end

  describe "do_query/3" do
    test "returns original query when both values are nil" do
      base_query = from(TestItem)

      query = RangeFilter.do_query({nil, nil}, base_query, :price)

      assert query == base_query
    end

    test "applies >= condition when only start is provided" do
      base_query = from(TestItem)

      query = RangeFilter.do_query({10, nil}, base_query, :price)

      assert [%{expr: where_expr}] = query.wheres
      assert match?({:>=, _, _}, where_expr)
    end

    test "applies <= condition when only end is provided" do
      base_query = from(TestItem)

      query = RangeFilter.do_query({nil, 100}, base_query, :price)

      assert [%{expr: where_expr}] = query.wheres
      assert match?({:<=, _, _}, where_expr)
    end

    test "applies between condition when both are provided" do
      base_query = from(TestItem)

      query = RangeFilter.do_query({10, 100}, base_query, :price)

      assert [%{expr: where_expr}] = query.wheres
      assert match?({:and, _, _}, where_expr)
    end
  end

  describe "changeset/3 with :number type" do
    test "validates valid number range" do
      changeset =
        {%{}, %{amount: :map}}
        |> Ecto.Changeset.cast(%{amount: %{"start" => "10", "end" => "100"}}, [:amount])

      result = RangeFilter.changeset(changeset, :amount, :number)

      assert result.valid?
    end

    test "validates valid number range with floats when the field type is unknown" do
      changeset =
        {%{}, %{amount: :map}}
        |> Ecto.Changeset.cast(%{amount: %{"start" => "10.5", "end" => "100.75"}}, [:amount])

      result = RangeFilter.changeset(changeset, :amount, :number)

      assert result.valid?
    end

    test "validates valid number range with floats on a decimal field" do
      result = number_changeset(:price, %{"start" => "10.5", "end" => "100.75"}, @assigns)

      assert result.valid?
    end

    test "validates valid number range with integers on an integer field" do
      result = number_changeset(:quantity, %{"start" => "10", "end" => "100"}, @assigns)

      assert result.valid?
    end

    for value <- ["1.5", "5.0", "1e2"] do
      test "returns error for start value #{value} on an integer field" do
        result = number_changeset(:quantity, %{"start" => unquote(value), "end" => ""}, @assigns)

        refute result.valid?
        assert result.errors == [quantity: {"has invalid start value", []}]
      end

      test "returns error for end value #{value} on an integer field" do
        result = number_changeset(:quantity, %{"start" => "", "end" => unquote(value)}, @assigns)

        refute result.valid?
        assert result.errors == [quantity: {"has invalid end value", []}]
      end
    end

    test "returns error for invalid start number" do
      changeset =
        {%{}, %{amount: :map}}
        |> Ecto.Changeset.cast(%{amount: %{"start" => "not-a-number", "end" => "100"}}, [:amount])

      result = RangeFilter.changeset(changeset, :amount, :number)

      refute result.valid?
      assert Keyword.has_key?(result.errors, :amount)
    end

    test "returns error for invalid end number" do
      changeset =
        {%{}, %{amount: :map}}
        |> Ecto.Changeset.cast(%{amount: %{"start" => "10", "end" => "abc"}}, [:amount])

      result = RangeFilter.changeset(changeset, :amount, :number)

      refute result.valid?
      assert Keyword.has_key?(result.errors, :amount)
    end

    test "returns error when start is greater than end" do
      changeset =
        {%{}, %{amount: :map}}
        |> Ecto.Changeset.cast(%{amount: %{"start" => "100", "end" => "10"}}, [:amount])

      result = RangeFilter.changeset(changeset, :amount, :number)

      refute result.valid?
      assert Keyword.has_key?(result.errors, :amount)
    end

    test "accepts partial range with only start" do
      changeset =
        {%{}, %{amount: :map}}
        |> Ecto.Changeset.cast(%{amount: %{"start" => "10", "end" => ""}}, [:amount])

      result = RangeFilter.changeset(changeset, :amount, :number)

      assert result.valid?
    end

    test "accepts partial range with only end" do
      changeset =
        {%{}, %{amount: :map}}
        |> Ecto.Changeset.cast(%{amount: %{"start" => "", "end" => "100"}}, [:amount])

      result = RangeFilter.changeset(changeset, :amount, :number)

      assert result.valid?
    end

    test "accepts empty range" do
      changeset =
        {%{}, %{amount: :map}}
        |> Ecto.Changeset.cast(%{amount: %{"start" => "", "end" => ""}}, [:amount])

      result = RangeFilter.changeset(changeset, :amount, :number)

      assert result.valid?
    end
  end

  describe "changeset/3 with :date type" do
    test "validates valid date range" do
      changeset =
        {%{}, %{date_range: :map}}
        |> Ecto.Changeset.cast(%{date_range: %{"start" => "2024-01-01", "end" => "2024-12-31"}}, [:date_range])

      result = RangeFilter.changeset(changeset, :date_range, :date)

      assert result.valid?
    end

    test "returns error for invalid start date" do
      changeset =
        {%{}, %{date_range: :map}}
        |> Ecto.Changeset.cast(%{date_range: %{"start" => "not-a-date", "end" => "2024-12-31"}}, [:date_range])

      result = RangeFilter.changeset(changeset, :date_range, :date)

      refute result.valid?
      assert Keyword.has_key?(result.errors, :date_range)
    end

    test "returns error for invalid end date" do
      changeset =
        {%{}, %{date_range: :map}}
        |> Ecto.Changeset.cast(%{date_range: %{"start" => "2024-01-01", "end" => "invalid"}}, [:date_range])

      result = RangeFilter.changeset(changeset, :date_range, :date)

      refute result.valid?
      assert Keyword.has_key?(result.errors, :date_range)
    end

    test "returns error when start date is after end date" do
      changeset =
        {%{}, %{date_range: :map}}
        |> Ecto.Changeset.cast(%{date_range: %{"start" => "2024-12-31", "end" => "2024-01-01"}}, [:date_range])

      result = RangeFilter.changeset(changeset, :date_range, :date)

      refute result.valid?
      assert Keyword.has_key?(result.errors, :date_range)
    end

    test "accepts same start and end date" do
      changeset =
        {%{}, %{date_range: :map}}
        |> Ecto.Changeset.cast(%{date_range: %{"start" => "2024-06-15", "end" => "2024-06-15"}}, [:date_range])

      result = RangeFilter.changeset(changeset, :date_range, :date)

      assert result.valid?
    end

    test "accepts partial range with only start date" do
      changeset =
        {%{}, %{date_range: :map}}
        |> Ecto.Changeset.cast(%{date_range: %{"start" => "2024-01-01", "end" => ""}}, [:date_range])

      result = RangeFilter.changeset(changeset, :date_range, :date)

      assert result.valid?
    end

    test "accepts partial range with only end date" do
      changeset =
        {%{}, %{date_range: :map}}
        |> Ecto.Changeset.cast(%{date_range: %{"start" => "", "end" => "2024-12-31"}}, [:date_range])

      result = RangeFilter.changeset(changeset, :date_range, :date)

      assert result.valid?
    end
  end

  describe "changeset/3 with :datetime type" do
    test "validates valid datetime range" do
      changeset =
        {%{}, %{datetime_range: :map}}
        |> Ecto.Changeset.cast(%{datetime_range: %{"start" => "2024-01-01", "end" => "2024-12-31"}}, [:datetime_range])

      result = RangeFilter.changeset(changeset, :datetime_range, :datetime)

      assert result.valid?
    end

    test "returns error for invalid start datetime" do
      changeset =
        {%{}, %{datetime_range: :map}}
        |> Ecto.Changeset.cast(%{datetime_range: %{"start" => "invalid", "end" => "2024-12-31"}}, [:datetime_range])

      result = RangeFilter.changeset(changeset, :datetime_range, :datetime)

      refute result.valid?
      assert Keyword.has_key?(result.errors, :datetime_range)
    end

    test "returns error when start datetime is after end datetime" do
      changeset =
        {%{}, %{datetime_range: :map}}
        |> Ecto.Changeset.cast(%{datetime_range: %{"start" => "2024-12-31", "end" => "2024-01-01"}}, [:datetime_range])

      result = RangeFilter.changeset(changeset, :datetime_range, :datetime)

      refute result.valid?
      assert Keyword.has_key?(result.errors, :datetime_range)
    end
  end
end
