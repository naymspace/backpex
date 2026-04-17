defmodule Backpex.Filters.BooleanTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  alias Backpex.Filters.Boolean, as: BooleanFilter

  doctest BooleanFilter

  defmodule TestItem do
    use Ecto.Schema

    @primary_key {:id, :id, autogenerate: false}
    schema "items" do
      field :published, :boolean
      field :featured, :boolean
      field :status, :string
    end
  end

  defp test_options do
    [
      %{
        label: "Published",
        key: "published",
        predicate: dynamic([x], x.published == true)
      },
      %{
        label: "Not published",
        key: "not_published",
        predicate: dynamic([x], x.published == false)
      },
      %{
        label: "Featured",
        key: "featured",
        predicate: dynamic([x], x.featured == true)
      }
    ]
  end

  describe "query/5" do
    test "returns original query when value is empty list" do
      base_query = from(TestItem)

      query = BooleanFilter.query(base_query, test_options(), :published, [], %{})

      assert query == base_query
    end

    test "applies single predicate when one option is selected" do
      base_query = from(TestItem)

      query = BooleanFilter.query(base_query, test_options(), :published, ["published"], %{})

      assert [%{expr: where_expr}] = query.wheres
      assert match?({:==, _, _}, where_expr)
    end

    test "applies OR of predicates when multiple options are selected" do
      base_query = from(TestItem)

      query = BooleanFilter.query(base_query, test_options(), :published, ["published", "featured"], %{})

      assert [%{expr: where_expr}] = query.wheres
      assert match?({:or, _, _}, where_expr)
    end

    test "applies OR of all predicates when all options are selected" do
      base_query = from(TestItem)

      query =
        BooleanFilter.query(
          base_query,
          test_options(),
          :published,
          ["published", "not_published", "featured"],
          %{}
        )

      assert [%{expr: where_expr}] = query.wheres
      assert match?({:or, _, _}, where_expr)
    end
  end

  describe "maybe_query/2" do
    test "returns original query when predicates is nil" do
      base_query = from(TestItem)

      query = BooleanFilter.maybe_query(nil, base_query)

      assert query == base_query
    end

    test "applies where clause when predicates are provided" do
      base_query = from(TestItem)
      predicate = dynamic([x], x.published == true)

      query = BooleanFilter.maybe_query(predicate, base_query)

      assert [%{expr: _where_expr}] = query.wheres
    end
  end

  describe "changeset/3" do
    test "validates selected keys exist in options" do
      changeset = {%{}, %{filter: {:array, :string}}} |> Ecto.Changeset.cast(%{filter: ["published"]}, [:filter])

      result = BooleanFilter.changeset(changeset, :filter, test_options())

      assert result.valid?
    end

    test "validates multiple selected keys exist in options" do
      changeset =
        {%{}, %{filter: {:array, :string}}}
        |> Ecto.Changeset.cast(%{filter: ["published", "featured"]}, [:filter])

      result = BooleanFilter.changeset(changeset, :filter, test_options())

      assert result.valid?
    end

    test "returns error for invalid option key" do
      changeset =
        {%{}, %{filter: {:array, :string}}}
        |> Ecto.Changeset.cast(%{filter: ["invalid_key"]}, [:filter])

      result = BooleanFilter.changeset(changeset, :filter, test_options())

      refute result.valid?
      assert Keyword.has_key?(result.errors, :filter)
    end

    test "returns error when mix of valid and invalid keys" do
      changeset =
        {%{}, %{filter: {:array, :string}}}
        |> Ecto.Changeset.cast(%{filter: ["published", "invalid_key"]}, [:filter])

      result = BooleanFilter.changeset(changeset, :filter, test_options())

      refute result.valid?
      assert Keyword.has_key?(result.errors, :filter)
    end

    test "accepts empty list" do
      changeset =
        {%{}, %{filter: {:array, :string}}}
        |> Ecto.Changeset.cast(%{filter: []}, [:filter])

      result = BooleanFilter.changeset(changeset, :filter, test_options())

      assert result.valid?
    end

    test "accepts nil value" do
      changeset =
        {%{}, %{filter: {:array, :string}}}
        |> Ecto.Changeset.cast(%{}, [:filter])

      result = BooleanFilter.changeset(changeset, :filter, test_options())

      assert result.valid?
    end
  end
end
