defmodule Backpex.Filters.SelectTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  alias Backpex.Filters.Select, as: SelectFilter

  doctest SelectFilter

  defmodule TestItem do
    use Ecto.Schema

    @primary_key {:id, :id, autogenerate: false}
    schema "items" do
      field :status, :string
      field :category, :string
      field :priority, :integer
    end
  end

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

end
