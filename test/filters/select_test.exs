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

  describe "changeset/3" do
    defp test_options do
      [{"Open", :open}, {"Closed", :closed}, {"Pending", "pending"}]
    end

    test "validates selected value exists in options (atom)" do
      changeset = {%{}, %{status: :string}} |> Ecto.Changeset.cast(%{status: "open"}, [:status])

      result = SelectFilter.changeset(changeset, :status, test_options())

      assert result.valid?
    end

    test "validates selected value exists in options (string)" do
      changeset = {%{}, %{status: :string}} |> Ecto.Changeset.cast(%{status: "pending"}, [:status])

      result = SelectFilter.changeset(changeset, :status, test_options())

      assert result.valid?
    end

    test "returns error for invalid option value" do
      changeset = {%{}, %{status: :string}} |> Ecto.Changeset.cast(%{status: "invalid"}, [:status])

      result = SelectFilter.changeset(changeset, :status, test_options())

      refute result.valid?
      assert Keyword.has_key?(result.errors, :status)
    end

    test "accepts nil value" do
      changeset = {%{}, %{status: :string}} |> Ecto.Changeset.cast(%{}, [:status])

      result = SelectFilter.changeset(changeset, :status, test_options())

      assert result.valid?
    end

    test "accepts empty string value" do
      changeset = {%{}, %{status: :string}} |> Ecto.Changeset.cast(%{status: ""}, [:status])

      result = SelectFilter.changeset(changeset, :status, test_options())

      assert result.valid?
    end
  end
end
