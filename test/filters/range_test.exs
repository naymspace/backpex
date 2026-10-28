defmodule Backpex.Filters.RangeTest do
  use ExUnit.Case, async: true

  import Ecto.Query, only: [from: 1]

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

  defmodule LikeRange do
    use Backpex.Filters.Range

    @impl Backpex.Filters.Range
    def type, do: :number

    @impl Backpex.Filter
    def label, do: "Likes"
  end

  describe "condition/4 with :number type" do
    test "returns nil when both start and end are empty" do
      assert RangeFilter.condition(:number, :price, %{"start" => "", "end" => ""}, %{}) == nil
    end

    test "keeps the items from the start when only start is provided" do
      assert RangeFilter.condition(:number, :price, %{"start" => "10", "end" => ""}, %{}) == {:>=, :price, 10}
    end

    test "keeps the items up to the end when only end is provided" do
      assert RangeFilter.condition(:number, :price, %{"start" => "", "end" => "100"}, %{}) == {:<=, :price, 100}
    end

    test "keeps the items between start and end when both are provided" do
      assert RangeFilter.condition(:number, :price, %{"start" => "10", "end" => "99.5"}, %{}) ==
               {:and, [{:>=, :price, 10}, {:<=, :price, 99.5}]}
    end

    test "returns nil for a value without start and end" do
      assert RangeFilter.condition(:number, :price, %{}, %{}) == nil
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

  @assigns %{live_resource: TestLiveResource}

  defp number_changeset(field, value, assigns) do
    {%{}, %{field => :map}}
    |> Ecto.Changeset.cast(%{field => value}, [field])
    |> RangeFilter.changeset(field, :number, assigns)
  end

  describe "condition/4 with :date type" do
    test "returns nil when both start and end are empty" do
      assert RangeFilter.condition(:date, :created_at, %{"start" => "", "end" => ""}, %{}) == nil
    end

    test "keeps the items from a valid start date" do
      assert RangeFilter.condition(:date, :created_at, %{"start" => "2024-01-01", "end" => ""}, %{}) ==
               {:>=, :created_at, "2024-01-01"}
    end

    test "keeps the items up to a valid end date" do
      assert RangeFilter.condition(:date, :created_at, %{"start" => "", "end" => "2024-12-31"}, %{}) ==
               {:<=, :created_at, "2024-12-31"}
    end

    test "returns nil for an invalid date format" do
      value = %{"start" => "not-a-date", "end" => "also-not-a-date"}

      assert RangeFilter.condition(:date, :created_at, value, %{}) == nil
    end
  end

  describe "condition/4 with :number type on an integer field" do
    test "ignores decimal boundaries" do
      for value <- ["1.5", "5.0", "1e2"] do
        assert RangeFilter.condition(:number, :quantity, %{"start" => value, "end" => "10"}, @assigns) ==
                 {:<=, :quantity, 10}
      end
    end

    test "keeps integer boundaries" do
      assert RangeFilter.condition(:number, :quantity, %{"start" => "2", "end" => "10"}, @assigns) ==
               {:and, [{:>=, :quantity, 2}, {:<=, :quantity, 10}]}
    end
  end

  describe "filter validation and condition on an integer field" do
    test "a decimal value is invalid and not applied to the query" do
      filter_configs = [quantity: %{module: QuantityRange}]
      params = %{"quantity" => %{"start" => "1.5", "end" => ""}}

      changeset = Backpex.FilterValidation.build_changeset(params, filter_configs, @assigns)
      filter_values = Backpex.FilterValidation.valid_values(changeset)
      query = TestItem |> from() |> Backpex.Adapters.Ecto.apply_filters(filter_values, filter_configs, @assigns)

      assert changeset.errors == [quantity: {"has invalid start value", []}]
      assert filter_values == %{}
      assert query.wheres == []
    end
  end

  describe "condition/4 with :datetime type" do
    test "returns nil when both start and end are empty" do
      assert RangeFilter.condition(:datetime, :updated_at, %{"start" => "", "end" => ""}, %{}) == nil
    end

    test "keeps the items from the start of the start date" do
      assert RangeFilter.condition(:datetime, :updated_at, %{"start" => "2024-01-01", "end" => ""}, %{}) ==
               {:>=, :updated_at, "2024-01-01T00:00:00+00:00"}
    end

    test "keeps the items up to the end of the end date" do
      assert RangeFilter.condition(:datetime, :updated_at, %{"start" => "", "end" => "2024-12-31"}, %{}) ==
               {:<=, :updated_at, "2024-12-31T23:59:59+00:00"}
    end
  end

  test "is the condition of a filter module, with its type" do
    assert LikeRange.condition(:likes, %{"start" => "5", "end" => ""}, %{}) == {:>=, :likes, 5}
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
