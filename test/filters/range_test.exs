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
end
