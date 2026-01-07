defmodule Backpex.Filters.SelectTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  alias Backpex.Filters.Select, as: SelectFilter

  defmodule TestItem do
    use Ecto.Schema

    @primary_key {:id, :id, autogenerate: false}
    schema "items" do
      field :status, :string
      field :category, :string
      field :priority, :integer
    end
  end

  @test_options [
    {"Open", :open},
    {"Closed", :closed},
    {"Pending", :pending}
  ]

  describe "query/4" do
    test "applies equality condition for attribute" do
      base_query = from(TestItem)

      query = SelectFilter.query(base_query, :status, "open", %{})

      assert [%{expr: where_expr}] = query.wheres
      assert match?({:==, _, _}, where_expr)
    end

    test "works with string values" do
      base_query = from(TestItem)

      query = SelectFilter.query(base_query, :category, "electronics", %{})

      assert [%{expr: where_expr}] = query.wheres
      assert match?({:==, _, _}, where_expr)
    end

    test "works with different attribute names" do
      base_query = from(TestItem)

      query = SelectFilter.query(base_query, :priority, 1, %{})

      assert [%{expr: where_expr}] = query.wheres
      assert match?({:==, _, _}, where_expr)
    end
  end

  describe "selected/1" do
    test "returns nil for empty string" do
      assert SelectFilter.selected("") == nil
    end

    test "returns value for non-empty string" do
      assert SelectFilter.selected("open") == "open"
    end

    test "returns atom value as-is" do
      assert SelectFilter.selected(:open) == :open
    end

    test "returns integer value as-is" do
      assert SelectFilter.selected(1) == 1
    end
  end

  describe "option_value_to_label/2" do
    test "finds label for matching string value" do
      assert SelectFilter.option_value_to_label(@test_options, "open") == "Open"
      assert SelectFilter.option_value_to_label(@test_options, "closed") == "Closed"
    end

    test "finds label for matching atom value" do
      assert SelectFilter.option_value_to_label(@test_options, :open) == "Open"
      assert SelectFilter.option_value_to_label(@test_options, :pending) == "Pending"
    end

    test "returns nil for unknown value" do
      assert SelectFilter.option_value_to_label(@test_options, "unknown") == nil
    end

    test "handles options with string keys" do
      options = [{"Active", "active"}, {"Inactive", "inactive"}]

      assert SelectFilter.option_value_to_label(options, "active") == "Active"
      assert SelectFilter.option_value_to_label(options, :active) == "Active"
    end

    test "handles empty options list" do
      assert SelectFilter.option_value_to_label([], "value") == nil
    end
  end
end
