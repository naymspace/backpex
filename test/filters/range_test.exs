defmodule Backpex.Filters.RangeTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  alias Backpex.Filters.Range, as: RangeFilter

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

  describe "maybe_parse/3" do
    test "returns nil for empty string" do
      assert RangeFilter.maybe_parse(:number, "") == nil
      assert RangeFilter.maybe_parse(:date, "") == nil
      assert RangeFilter.maybe_parse(:datetime, "") == nil
    end

    test "parses valid date for :date type" do
      assert RangeFilter.maybe_parse(:date, "2024-06-15") == "2024-06-15"
    end

    test "returns nil for invalid date" do
      assert RangeFilter.maybe_parse(:date, "not-a-date") == nil
      assert RangeFilter.maybe_parse(:date, "2024-13-45") == nil
    end

    test "appends T00:00:00+00:00 for datetime start" do
      result = RangeFilter.maybe_parse(:datetime, "2024-01-01", false)
      assert result == "2024-01-01T00:00:00+00:00"
    end

    test "appends T23:59:59+00:00 for datetime end" do
      result = RangeFilter.maybe_parse(:datetime, "2024-12-31", true)
      assert result == "2024-12-31T23:59:59+00:00"
    end

    test "returns nil for invalid datetime date" do
      assert RangeFilter.maybe_parse(:datetime, "invalid") == nil
    end
  end

  describe "parse_float_or_int/1" do
    test "parses integer string" do
      assert RangeFilter.parse_float_or_int("42") == 42
      assert RangeFilter.parse_float_or_int("-10") == -10
      assert RangeFilter.parse_float_or_int("0") == 0
    end

    test "parses float string" do
      assert RangeFilter.parse_float_or_int("3.14") == 3.14
      assert RangeFilter.parse_float_or_int("-2.5") == -2.5
      assert RangeFilter.parse_float_or_int("0.0") == 0.0
    end

    test "returns nil for invalid input" do
      assert RangeFilter.parse_float_or_int("not-a-number") == nil
      assert RangeFilter.parse_float_or_int("abc123") == nil
      assert RangeFilter.parse_float_or_int("12abc") == nil
      assert RangeFilter.parse_float_or_int("") == nil
    end

    test "prefers integer over float for whole numbers" do
      result = RangeFilter.parse_float_or_int("42")
      assert is_integer(result)
      assert result == 42
    end
  end

  describe "maybe_parse_range/2" do
    test "parses both start and end for number type" do
      assert RangeFilter.maybe_parse_range(:number, "10", "100") == {10, 100}
    end

    test "handles nil for missing values" do
      assert RangeFilter.maybe_parse_range(:number, "", "100") == {nil, 100}
      assert RangeFilter.maybe_parse_range(:number, "10", "") == {10, nil}
      assert RangeFilter.maybe_parse_range(:number, "", "") == {nil, nil}
    end

    test "parses dates correctly" do
      assert RangeFilter.maybe_parse_range(:date, "2024-01-01", "2024-12-31") ==
               {"2024-01-01", "2024-12-31"}
    end

    test "adds time boundaries for datetime type" do
      {start_dt, end_dt} = RangeFilter.maybe_parse_range(:datetime, "2024-01-01", "2024-12-31")
      assert start_dt == "2024-01-01T00:00:00+00:00"
      assert end_dt == "2024-12-31T23:59:59+00:00"
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

  describe "date?/1" do
    test "returns true for valid ISO 8601 date" do
      assert RangeFilter.date?("2024-01-01") == true
      assert RangeFilter.date?("2023-12-31") == true
      assert RangeFilter.date?("2000-06-15") == true
    end

    test "returns false for invalid date" do
      assert RangeFilter.date?("not-a-date") == false
      assert RangeFilter.date?("2024-13-01") == false
      assert RangeFilter.date?("2024-01-32") == false
      assert RangeFilter.date?("") == false
    end
  end

  describe "render_type/1" do
    test "returns :date for datetime type" do
      assert RangeFilter.render_type(:datetime) == :date
    end

    test "returns same type for other types" do
      assert RangeFilter.render_type(:date) == :date
      assert RangeFilter.render_type(:number) == :number
    end
  end
end
