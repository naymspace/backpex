defmodule Backpex.Filters.MultiSelectTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  alias Backpex.Filters.MultiSelect, as: MultiSelectFilter

  doctest MultiSelectFilter

  defmodule TestItem do
    use Ecto.Schema

    @primary_key {:id, :id, autogenerate: false}
    schema "items" do
      field :status, :string
      field :user_id, :binary_id
      field :category, :string
    end
  end

  describe "query/4" do
    test "returns original query when value is empty list" do
      base_query = from(TestItem)

      query = MultiSelectFilter.query(base_query, :user_id, [], %{})

      assert query == base_query
    end

    test "applies IN condition for single value" do
      base_query = from(TestItem)

      query = MultiSelectFilter.query(base_query, :user_id, ["acdd1860-65ce-4ed6-a37c-433851cf68d7"], %{})

      assert [%{expr: where_expr}] = query.wheres
      assert match?({:in, _, _}, where_expr)
    end

    test "applies IN condition for multiple values" do
      base_query = from(TestItem)
      values = ["acdd1860-65ce-4ed6-a37c-433851cf68d7", "9d78ce5e-9334-4a6c-a076-f1e72522de2"]

      query = MultiSelectFilter.query(base_query, :user_id, values, %{})

      assert [%{expr: where_expr}] = query.wheres
      assert match?({:in, _, _}, where_expr)
    end

    test "works with string values" do
      base_query = from(TestItem)

      query = MultiSelectFilter.query(base_query, :status, ["open", "pending"], %{})

      assert [%{expr: where_expr}] = query.wheres
      assert match?({:in, _, _}, where_expr)
    end

    test "works with different attribute names" do
      base_query = from(TestItem)

      query = MultiSelectFilter.query(base_query, :category, ["electronics", "books"], %{})

      assert [%{expr: where_expr}] = query.wheres
      assert match?({:in, _, _}, where_expr)
    end
  end

  describe "changeset/3" do
    defp test_options do
      [
        {"John Doe", "acdd1860-65ce-4ed6-a37c-433851cf68d7"},
        {"Jane Doe", "9d78ce5e-9334-4a6c-a076-f1e72522de2"},
        {"Bob Smith", :bob}
      ]
    end

    test "validates selected values exist in options (single)" do
      changeset =
        {%{}, %{users: {:array, :string}}}
        |> Ecto.Changeset.cast(%{users: ["acdd1860-65ce-4ed6-a37c-433851cf68d7"]}, [:users])

      result = MultiSelectFilter.changeset(changeset, :users, test_options())

      assert result.valid?
    end

    test "validates selected values exist in options (multiple)" do
      changeset =
        {%{}, %{users: {:array, :string}}}
        |> Ecto.Changeset.cast(
          %{users: ["acdd1860-65ce-4ed6-a37c-433851cf68d7", "9d78ce5e-9334-4a6c-a076-f1e72522de2"]},
          [:users]
        )

      result = MultiSelectFilter.changeset(changeset, :users, test_options())

      assert result.valid?
    end

    test "validates atom options converted to string" do
      changeset =
        {%{}, %{users: {:array, :string}}}
        |> Ecto.Changeset.cast(%{users: ["bob"]}, [:users])

      result = MultiSelectFilter.changeset(changeset, :users, test_options())

      assert result.valid?
    end

    test "returns error for invalid option value" do
      changeset =
        {%{}, %{users: {:array, :string}}}
        |> Ecto.Changeset.cast(%{users: ["invalid-uuid"]}, [:users])

      result = MultiSelectFilter.changeset(changeset, :users, test_options())

      refute result.valid?
      assert Keyword.has_key?(result.errors, :users)
    end

    test "returns error when mix of valid and invalid values" do
      changeset =
        {%{}, %{users: {:array, :string}}}
        |> Ecto.Changeset.cast(
          %{users: ["acdd1860-65ce-4ed6-a37c-433851cf68d7", "invalid-uuid"]},
          [:users]
        )

      result = MultiSelectFilter.changeset(changeset, :users, test_options())

      refute result.valid?
      assert Keyword.has_key?(result.errors, :users)
    end

    test "accepts empty list" do
      changeset =
        {%{}, %{users: {:array, :string}}}
        |> Ecto.Changeset.cast(%{users: []}, [:users])

      result = MultiSelectFilter.changeset(changeset, :users, test_options())

      assert result.valid?
    end

    test "accepts nil value" do
      changeset =
        {%{}, %{users: {:array, :string}}}
        |> Ecto.Changeset.cast(%{}, [:users])

      result = MultiSelectFilter.changeset(changeset, :users, test_options())

      assert result.valid?
    end
  end
end
