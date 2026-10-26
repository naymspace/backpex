defmodule Backpex.Filters.RangeTest do
  use ExUnit.Case, async: true

  alias Backpex.Filters.Range, as: RangeFilter

  doctest RangeFilter

  defmodule LikeRange do
    use Backpex.Filters.Range

    @impl Backpex.Filters.Range
    def type, do: :number

    @impl Backpex.Filter
    def label, do: "Likes"
  end

  describe "condition/3 with :number type" do
    test "returns nil when both start and end are empty" do
      assert RangeFilter.condition({:price, %{type: :number}}, %{"start" => "", "end" => ""}, %{}) == nil
    end

    test "keeps the items from the start when only start is provided" do
      assert RangeFilter.condition({:price, %{type: :number}}, %{"start" => "10", "end" => ""}, %{}) ==
               {:>=, :price, 10}
    end

    test "keeps the items up to the end when only end is provided" do
      assert RangeFilter.condition({:price, %{type: :number}}, %{"start" => "", "end" => "100"}, %{}) ==
               {:<=, :price, 100}
    end

    test "keeps the items between start and end when both are provided" do
      assert RangeFilter.condition({:price, %{type: :number}}, %{"start" => "10", "end" => "99.5"}, %{}) ==
               {:and, [{:>=, :price, 10}, {:<=, :price, 99.5}]}
    end

    test "returns nil for a value without start and end" do
      assert RangeFilter.condition({:price, %{type: :number}}, %{}, %{}) == nil
    end
  end

  describe "condition/3 with :date type" do
    test "returns nil when both start and end are empty" do
      assert RangeFilter.condition({:created_at, %{type: :date}}, %{"start" => "", "end" => ""}, %{}) == nil
    end

    test "keeps the items from a valid start date" do
      assert RangeFilter.condition({:created_at, %{type: :date}}, %{"start" => "2024-01-01", "end" => ""}, %{}) ==
               {:>=, :created_at, "2024-01-01"}
    end

    test "keeps the items up to a valid end date" do
      assert RangeFilter.condition({:created_at, %{type: :date}}, %{"start" => "", "end" => "2024-12-31"}, %{}) ==
               {:<=, :created_at, "2024-12-31"}
    end

    test "returns nil for an invalid date format" do
      value = %{"start" => "not-a-date", "end" => "also-not-a-date"}

      assert RangeFilter.condition({:created_at, %{type: :date}}, value, %{}) == nil
    end
  end

  describe "condition/3 with :datetime type" do
    test "returns nil when both start and end are empty" do
      assert RangeFilter.condition({:updated_at, %{type: :datetime}}, %{"start" => "", "end" => ""}, %{}) == nil
    end

    test "keeps the items from the start of the start date" do
      assert RangeFilter.condition({:updated_at, %{type: :datetime}}, %{"start" => "2024-01-01", "end" => ""}, %{}) ==
               {:>=, :updated_at, "2024-01-01T00:00:00+00:00"}
    end

    test "keeps the items up to the end of the end date" do
      assert RangeFilter.condition({:updated_at, %{type: :datetime}}, %{"start" => "", "end" => "2024-12-31"}, %{}) ==
               {:<=, :updated_at, "2024-12-31T23:59:59+00:00"}
    end
  end

  test "is the condition of a filter module, with its type" do
    filter = Backpex.Filter.validate_config!({:likes, %{module: LikeRange}}, __MODULE__)

    assert LikeRange.condition(
             filter,
             %{"start" => "5", "end" => ""},
             %{}
           ) == {:>=, :likes, 5}
  end

  describe "changeset/3 with :number type" do
    test "validates valid number range" do
      changeset =
        {%{}, %{amount: :map}}
        |> Ecto.Changeset.cast(%{amount: %{"start" => "10", "end" => "100"}}, [:amount])

      result = RangeFilter.changeset(changeset, {:amount, %{type: :number}}, %{})

      assert result.valid?
    end

    test "validates valid number range with floats" do
      changeset =
        {%{}, %{amount: :map}}
        |> Ecto.Changeset.cast(%{amount: %{"start" => "10.5", "end" => "100.75"}}, [:amount])

      result = RangeFilter.changeset(changeset, {:amount, %{type: :number}}, %{})

      assert result.valid?
    end

    test "returns error for invalid start number" do
      changeset =
        {%{}, %{amount: :map}}
        |> Ecto.Changeset.cast(%{amount: %{"start" => "not-a-number", "end" => "100"}}, [:amount])

      result = RangeFilter.changeset(changeset, {:amount, %{type: :number}}, %{})

      refute result.valid?
      assert Keyword.has_key?(result.errors, :amount)
    end

    test "returns error for invalid end number" do
      changeset =
        {%{}, %{amount: :map}}
        |> Ecto.Changeset.cast(%{amount: %{"start" => "10", "end" => "abc"}}, [:amount])

      result = RangeFilter.changeset(changeset, {:amount, %{type: :number}}, %{})

      refute result.valid?
      assert Keyword.has_key?(result.errors, :amount)
    end

    test "returns error when start is greater than end" do
      changeset =
        {%{}, %{amount: :map}}
        |> Ecto.Changeset.cast(%{amount: %{"start" => "100", "end" => "10"}}, [:amount])

      result = RangeFilter.changeset(changeset, {:amount, %{type: :number}}, %{})

      refute result.valid?
      assert Keyword.has_key?(result.errors, :amount)
    end

    test "accepts partial range with only start" do
      changeset =
        {%{}, %{amount: :map}}
        |> Ecto.Changeset.cast(%{amount: %{"start" => "10", "end" => ""}}, [:amount])

      result = RangeFilter.changeset(changeset, {:amount, %{type: :number}}, %{})

      assert result.valid?
    end

    test "accepts partial range with only end" do
      changeset =
        {%{}, %{amount: :map}}
        |> Ecto.Changeset.cast(%{amount: %{"start" => "", "end" => "100"}}, [:amount])

      result = RangeFilter.changeset(changeset, {:amount, %{type: :number}}, %{})

      assert result.valid?
    end

    test "accepts empty range" do
      changeset =
        {%{}, %{amount: :map}}
        |> Ecto.Changeset.cast(%{amount: %{"start" => "", "end" => ""}}, [:amount])

      result = RangeFilter.changeset(changeset, {:amount, %{type: :number}}, %{})

      assert result.valid?
    end
  end

  describe "changeset/3 with :date type" do
    test "validates valid date range" do
      changeset =
        {%{}, %{date_range: :map}}
        |> Ecto.Changeset.cast(%{date_range: %{"start" => "2024-01-01", "end" => "2024-12-31"}}, [:date_range])

      result = RangeFilter.changeset(changeset, {:date_range, %{type: :date}}, %{})

      assert result.valid?
    end

    test "returns error for invalid start date" do
      changeset =
        {%{}, %{date_range: :map}}
        |> Ecto.Changeset.cast(%{date_range: %{"start" => "not-a-date", "end" => "2024-12-31"}}, [:date_range])

      result = RangeFilter.changeset(changeset, {:date_range, %{type: :date}}, %{})

      refute result.valid?
      assert Keyword.has_key?(result.errors, :date_range)
    end

    test "returns error for invalid end date" do
      changeset =
        {%{}, %{date_range: :map}}
        |> Ecto.Changeset.cast(%{date_range: %{"start" => "2024-01-01", "end" => "invalid"}}, [:date_range])

      result = RangeFilter.changeset(changeset, {:date_range, %{type: :date}}, %{})

      refute result.valid?
      assert Keyword.has_key?(result.errors, :date_range)
    end

    test "returns error when start date is after end date" do
      changeset =
        {%{}, %{date_range: :map}}
        |> Ecto.Changeset.cast(%{date_range: %{"start" => "2024-12-31", "end" => "2024-01-01"}}, [:date_range])

      result = RangeFilter.changeset(changeset, {:date_range, %{type: :date}}, %{})

      refute result.valid?
      assert Keyword.has_key?(result.errors, :date_range)
    end

    test "accepts same start and end date" do
      changeset =
        {%{}, %{date_range: :map}}
        |> Ecto.Changeset.cast(%{date_range: %{"start" => "2024-06-15", "end" => "2024-06-15"}}, [:date_range])

      result = RangeFilter.changeset(changeset, {:date_range, %{type: :date}}, %{})

      assert result.valid?
    end

    test "accepts partial range with only start date" do
      changeset =
        {%{}, %{date_range: :map}}
        |> Ecto.Changeset.cast(%{date_range: %{"start" => "2024-01-01", "end" => ""}}, [:date_range])

      result = RangeFilter.changeset(changeset, {:date_range, %{type: :date}}, %{})

      assert result.valid?
    end

    test "accepts partial range with only end date" do
      changeset =
        {%{}, %{date_range: :map}}
        |> Ecto.Changeset.cast(%{date_range: %{"start" => "", "end" => "2024-12-31"}}, [:date_range])

      result = RangeFilter.changeset(changeset, {:date_range, %{type: :date}}, %{})

      assert result.valid?
    end
  end

  describe "changeset/3 with :datetime type" do
    test "validates valid datetime range" do
      changeset =
        {%{}, %{datetime_range: :map}}
        |> Ecto.Changeset.cast(%{datetime_range: %{"start" => "2024-01-01", "end" => "2024-12-31"}}, [:datetime_range])

      result = RangeFilter.changeset(changeset, {:datetime_range, %{type: :datetime}}, %{})

      assert result.valid?
    end

    test "returns error for invalid start datetime" do
      changeset =
        {%{}, %{datetime_range: :map}}
        |> Ecto.Changeset.cast(%{datetime_range: %{"start" => "invalid", "end" => "2024-12-31"}}, [:datetime_range])

      result = RangeFilter.changeset(changeset, {:datetime_range, %{type: :datetime}}, %{})

      refute result.valid?
      assert Keyword.has_key?(result.errors, :datetime_range)
    end

    test "returns error when start datetime is after end datetime" do
      changeset =
        {%{}, %{datetime_range: :map}}
        |> Ecto.Changeset.cast(%{datetime_range: %{"start" => "2024-12-31", "end" => "2024-01-01"}}, [:datetime_range])

      result = RangeFilter.changeset(changeset, {:datetime_range, %{type: :datetime}}, %{})

      refute result.valid?
      assert Keyword.has_key?(result.errors, :datetime_range)
    end
  end
end
