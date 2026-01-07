defmodule Backpex.Filters.MultiSelectTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  alias Backpex.Filters.MultiSelect, as: MultiSelectFilter

  defmodule TestItem do
    use Ecto.Schema

    @primary_key {:id, :id, autogenerate: false}
    schema "items" do
      field :status, :string
      field :user_id, :binary_id
      field :category, :string
    end
  end

  @test_options [
    {"John Doe", "acdd1860-65ce-4ed6-a37c-433851cf68d7"},
    {"Jane Doe", "9d78ce5e-9334-4a6c-a076-f1e72522de2"},
    {"Bob Smith", "a1b2c3d4-e5f6-7890-abcd-ef1234567890"}
  ]

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

  describe "option_value_to_label/2" do
    test "returns labels for selected values with comma separator" do
      values = ["acdd1860-65ce-4ed6-a37c-433851cf68d7", "9d78ce5e-9334-4a6c-a076-f1e72522de2"]

      result = MultiSelectFilter.option_value_to_label(@test_options, values)

      assert result == ["John Doe", ", ", "Jane Doe"]
    end

    test "returns single label for single value" do
      result = MultiSelectFilter.option_value_to_label(@test_options, ["acdd1860-65ce-4ed6-a37c-433851cf68d7"])

      assert result == ["John Doe"]
    end

    test "returns empty list for empty values" do
      result = MultiSelectFilter.option_value_to_label(@test_options, [])

      assert result == []
    end

    test "returns empty string for unknown key" do
      result = MultiSelectFilter.option_value_to_label(@test_options, ["unknown-uuid"])

      assert result == [""]
    end

    test "handles three values correctly" do
      values = [
        "acdd1860-65ce-4ed6-a37c-433851cf68d7",
        "9d78ce5e-9334-4a6c-a076-f1e72522de2",
        "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
      ]

      result = MultiSelectFilter.option_value_to_label(@test_options, values)

      assert result == ["John Doe", ", ", "Jane Doe", ", ", "Bob Smith"]
    end
  end

  describe "find_option_label/2" do
    test "finds label for existing key" do
      assert MultiSelectFilter.find_option_label(@test_options, "acdd1860-65ce-4ed6-a37c-433851cf68d7") ==
               "John Doe"

      assert MultiSelectFilter.find_option_label(@test_options, "9d78ce5e-9334-4a6c-a076-f1e72522de2") == "Jane Doe"
    end

    test "returns empty string for unknown key" do
      assert MultiSelectFilter.find_option_label(@test_options, "unknown") == ""
    end

    test "handles atom keys by converting to string" do
      options = [{"Active", :active}, {"Inactive", :inactive}]

      assert MultiSelectFilter.find_option_label(options, :active) == "Active"
      assert MultiSelectFilter.find_option_label(options, "active") == "Active"
    end

    test "returns empty string for nil key" do
      assert MultiSelectFilter.find_option_label(@test_options, nil) == ""
    end
  end
end
