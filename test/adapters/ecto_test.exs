defmodule Backpex.Adapters.EctoTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  alias Backpex.Adapters.Ecto, as: EctoAdapter
  alias Backpex.Fields.Text

  defmodule TestUser do
    use Ecto.Schema

    @primary_key {:id, :id, autogenerate: false}
    schema "users" do
      field :title, :string
      field :name, :string
      field :age, :integer
      field :active, :boolean
    end
  end

  defmodule TestFilter do
    @moduledoc false
    @behaviour Backpex.Filter

    @impl Backpex.Filter
    def label, do: "Test Filter"

    @impl Backpex.Filter
    def can?(_assigns), do: true

    @impl Backpex.Filter
    def query(query, attribute, value, _assigns) do
      where(query, [x], field(x, ^attribute) == ^value)
    end

    @impl Backpex.Filter
    def render(assigns), do: assigns

    @impl Backpex.Filter
    def render_form(assigns), do: assigns
  end

  defmodule TestRangeFilter do
    @moduledoc false
    @behaviour Backpex.Filter

    @impl Backpex.Filter
    def label, do: "Test Range Filter"

    @impl Backpex.Filter
    def can?(_assigns), do: true

    @impl Backpex.Filter
    def query(query, attribute, %{"start" => start_val, "end" => end_val}, _assigns) do
      query
      |> where([x], field(x, ^attribute) >= ^start_val)
      |> where([x], field(x, ^attribute) <= ^end_val)
    end

    @impl Backpex.Filter
    def render(assigns), do: assigns

    @impl Backpex.Filter
    def render_form(assigns), do: assigns
  end

  describe "apply_search/4 (without full text search configured)" do
    test "adds ilike condition for one field" do
      base_query = from(TestUser, as: ^EctoAdapter.name_by_schema(TestUser))

      searchable_fields = [
        {:title, %{module: Text, queryable: TestUser}}
      ]

      query = EctoAdapter.apply_search(base_query, TestUser, nil, {"foo", searchable_fields})

      assert [%{expr: ilike_expr}] = query.wheres
      assert match?({:ilike, _, _}, ilike_expr)

      expr_str = Macro.to_string(ilike_expr)
      assert expr_str =~ "title"
    end

    test "chains ilike conditions with OR for multiple fields" do
      base_query = from(TestUser, as: ^EctoAdapter.name_by_schema(TestUser))

      searchable_fields = [
        {:title, %{module: Text, queryable: TestUser}},
        {:name, %{module: Text, queryable: TestUser}}
      ]

      query = EctoAdapter.apply_search(base_query, TestUser, nil, {"bar", searchable_fields})

      assert [%{expr: or_expr}] = query.wheres
      assert match?({:or, _, _}, or_expr)

      expr_str = Macro.to_string(or_expr)
      assert expr_str =~ "title"
      assert expr_str =~ "name"
    end

    test "returns original query when no searchable fields provided" do
      base_query = from(TestUser, as: ^EctoAdapter.name_by_schema(TestUser))

      query = EctoAdapter.apply_search(base_query, TestUser, nil, {"baz", []})

      assert query == base_query
    end

    test "returns original query when empty search string provided" do
      base_query = from(TestUser, as: ^EctoAdapter.name_by_schema(TestUser))

      searchable_fields = [
        {:title, %{module: Text, queryable: TestUser}}
      ]

      query = EctoAdapter.apply_search(base_query, TestUser, nil, {"", searchable_fields})

      assert query == base_query
    end

    test "uses provided select expression for ilike" do
      base_query = from(TestUser, as: ^EctoAdapter.name_by_schema(TestUser))

      select_expr = dynamic([testuser: u], fragment("UPPER(?)", field(u, ^:name)))

      searchable_fields = [
        {:name_display, %{module: Text, select: select_expr}}
      ]

      query = EctoAdapter.apply_search(base_query, TestUser, nil, {"qux", searchable_fields})

      assert [%{expr: ilike_expr}] = query.wheres
      assert match?({:ilike, _, _}, ilike_expr)

      expr_str = Macro.to_string(ilike_expr)
      assert expr_str =~ "fragment"
      assert expr_str =~ "UPPER("
    end
  end

  describe "apply_search/4 (with full text search configured)" do
    test "returns original query on empty search string" do
      base_query = from(TestUser)

      query = EctoAdapter.apply_search(base_query, TestUser, :title, {"", []})

      assert query == base_query
    end

    test "adds tsquery fragment for non-empty search string" do
      base_query = from(TestUser, as: ^EctoAdapter.name_by_schema(TestUser))

      query = EctoAdapter.apply_search(base_query, TestUser, :title, {"hello world", []})

      assert [%{expr: fragment_expr}] = query.wheres
      assert match?({:fragment, _, _}, fragment_expr)

      expr_str = Macro.to_string(fragment_expr)
      assert expr_str =~ "websearch_to_tsquery"
      assert expr_str =~ "@@"
      assert expr_str =~ "title"
    end
  end

  describe "apply_criteria/3 ordering" do
    test "applies ascending order by single field" do
      base_query = from(TestUser, as: ^EctoAdapter.name_by_schema(TestUser))

      fields = [
        {:name, %{module: Text, queryable: TestUser}}
      ]

      criteria = [
        order: %{by: :name, direction: :asc, schema: TestUser, field_name: :name}
      ]

      query = EctoAdapter.apply_criteria(base_query, criteria, fields)

      assert %{order_bys: [%{expr: order_expr}]} = query
      assert [{:asc_nulls_first, _order_expression}] = order_expr
    end

    test "applies descending order by single field" do
      base_query = from(TestUser, as: ^EctoAdapter.name_by_schema(TestUser))

      fields = [
        {:name, %{module: Text, queryable: TestUser}}
      ]

      criteria = [
        order: %{by: :name, direction: :desc, schema: TestUser, field_name: :name}
      ]

      query = EctoAdapter.apply_criteria(base_query, criteria, fields)

      assert %{order_bys: [%{expr: order_expr}]} = query
      assert [{:desc_nulls_last, _order_expression}] = order_expr
    end

    test "applies ordering with custom select expression" do
      base_query = from(TestUser, as: ^EctoAdapter.name_by_schema(TestUser))

      select_expr = dynamic([testuser: u], fragment("UPPER(?)", field(u, ^:name)))

      fields = [
        {:name, %{module: Text, queryable: TestUser, select: select_expr}}
      ]

      criteria = [
        order: %{by: :name, direction: :asc, schema: TestUser, field_name: :name}
      ]

      query = EctoAdapter.apply_criteria(base_query, criteria, fields)

      assert %{order_bys: [%{expr: order_expr}]} = query
      [{:asc_nulls_first, order_expression}] = order_expr

      expr_str = Macro.to_string(order_expression)
      assert expr_str =~ "fragment"
      assert expr_str =~ "UPPER("
    end
  end

  describe "apply_criteria/3 pagination" do
    test "applies limit and offset from pagination" do
      base_query = from(TestUser, as: ^EctoAdapter.name_by_schema(TestUser))

      fields = []

      criteria = [
        pagination: %{page: 3, size: 10}
      ]

      query = EctoAdapter.apply_criteria(base_query, criteria, fields)

      # Limit and offset are stored as pinned params
      assert %{limit: %{params: [{10, :integer}]}} = query
      assert %{offset: %{params: [{20, :integer}]}} = query
    end

    test "applies first page correctly with zero offset" do
      base_query = from(TestUser, as: ^EctoAdapter.name_by_schema(TestUser))

      fields = []

      criteria = [
        pagination: %{page: 1, size: 25}
      ]

      query = EctoAdapter.apply_criteria(base_query, criteria, fields)

      assert %{limit: %{params: [{25, :integer}]}} = query
      assert %{offset: %{params: [{0, :integer}]}} = query
    end

    test "applies simple limit without pagination" do
      base_query = from(TestUser, as: ^EctoAdapter.name_by_schema(TestUser))

      fields = []

      criteria = [
        limit: 5
      ]

      query = EctoAdapter.apply_criteria(base_query, criteria, fields)

      assert %{limit: %{params: [{5, :integer}]}} = query
      assert query.offset == nil
    end

    test "returns original query for empty criteria" do
      base_query = from(TestUser, as: ^EctoAdapter.name_by_schema(TestUser))

      query = EctoAdapter.apply_criteria(base_query, [], [])

      assert query == base_query
    end

    test "ignores unknown criteria" do
      base_query = from(TestUser, as: ^EctoAdapter.name_by_schema(TestUser))

      fields = []

      criteria = [
        unknown_option: "some_value",
        another_unknown: 123
      ]

      query = EctoAdapter.apply_criteria(base_query, criteria, fields)

      assert query == base_query
    end
  end

  describe "apply_filters/4" do
    test "returns original query when filter_values is empty" do
      base_query = from(TestUser, as: ^EctoAdapter.name_by_schema(TestUser))

      query = EctoAdapter.apply_filters(base_query, %{}, [], %{})

      assert query == base_query
    end

    test "applies single filter correctly" do
      base_query = from(TestUser, as: ^EctoAdapter.name_by_schema(TestUser))

      filter_values = %{active: true}
      filter_configs = [active: %{module: TestFilter}]

      query = EctoAdapter.apply_filters(base_query, filter_values, filter_configs, %{})

      assert [%{expr: where_expr}] = query.wheres
      assert match?({:==, _, _}, where_expr)

      expr_str = Macro.to_string(where_expr)
      assert expr_str =~ "active"
    end

    test "applies multiple filters with AND logic" do
      base_query = from(TestUser, as: ^EctoAdapter.name_by_schema(TestUser))

      filter_values = %{
        active: true,
        age: %{"start" => 18, "end" => 65}
      }

      filter_configs = [
        active: %{module: TestFilter},
        age: %{module: TestRangeFilter}
      ]

      query = EctoAdapter.apply_filters(base_query, filter_values, filter_configs, %{})

      # Should have 3 where clauses: active == true, age >= 18, age <= 65
      assert length(query.wheres) == 3
    end

    test "passes assigns to filter query function" do
      defmodule AssignsCapturingFilter do
        @moduledoc false
        @behaviour Backpex.Filter

        @impl Backpex.Filter
        def label, do: "Assigns Filter"

        @impl Backpex.Filter
        def query(query, _attribute, _value, assigns) do
          # Store the user_id from assigns in a where clause
          user_id = Map.get(assigns, :user_id, 0)
          where(query, [x], x.id == ^user_id)
        end

        @impl Backpex.Filter
        def render(assigns), do: assigns

        @impl Backpex.Filter
        def render_form(assigns), do: assigns

        @impl Backpex.Filter
        def can?(_assigns), do: true
      end

      base_query = from(TestUser, as: ^EctoAdapter.name_by_schema(TestUser))

      filter_values = %{owner: "any"}
      filter_configs = [owner: %{module: AssignsCapturingFilter}]

      assigns = %{user_id: 42}

      query = EctoAdapter.apply_filters(base_query, filter_values, filter_configs, assigns)

      assert [%{expr: _where_expr, params: params}] = query.wheres
      # The params should contain the user_id from assigns
      assert Enum.any?(params, fn {val, _type} -> val == 42 end)
    end

    test "skips filters without matching config" do
      base_query = from(TestUser, as: ^EctoAdapter.name_by_schema(TestUser))

      filter_values = %{active: true, unknown: "value"}
      filter_configs = [active: %{module: TestFilter}]

      query = EctoAdapter.apply_filters(base_query, filter_values, filter_configs, %{})

      # Only one filter applied (active), unknown is skipped
      assert [%{expr: where_expr}] = query.wheres
      assert match?({:==, _, _}, where_expr)
    end
  end

  describe "name_by_schema/1" do
    test "returns lowercase atom from module name" do
      assert EctoAdapter.name_by_schema(TestUser) == :testuser
    end

    test "returns last part of nested module name" do
      defmodule Nested.Deep.SomeSchema do
        use Ecto.Schema

        schema "some_schema" do
        end
      end

      assert EctoAdapter.name_by_schema(Nested.Deep.SomeSchema) == :someschema
    end
  end
end
