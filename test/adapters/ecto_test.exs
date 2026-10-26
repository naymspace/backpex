defmodule Backpex.Adapters.EctoTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  alias Backpex.Adapters.Ecto, as: EctoAdapter
  alias Backpex.Metrics.Value

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

  defmodule TestTag do
    use Ecto.Schema

    schema "tags" do
      field :name, :string
    end
  end

  defmodule TestPostTag do
    use Ecto.Schema

    schema "posts_tags" do
      belongs_to :post, Backpex.Adapters.EctoTest.TestPost
      belongs_to :tag, Backpex.Adapters.EctoTest.TestTag
    end
  end

  defmodule TestPost do
    use Ecto.Schema

    schema "posts" do
      field :title, :string
      belongs_to :user, Backpex.Adapters.EctoTest.TestUser
      has_many :post_tags, Backpex.Adapters.EctoTest.TestPostTag, foreign_key: :post_id
      has_many :tags, through: [:post_tags, :tag]
    end
  end

  defmodule FakeRepo do
    @moduledoc false
    # Reports every call as `{:repo, function, query}`. Returns what the test put into the process dictionary under
    # `{FakeRepo, function}`, or calls it with the query if it is a function.
    def all(query), do: reply(:all, query)
    def one(query), do: reply(:one, query)
    def aggregate(query, :count), do: reply(:aggregate, query)
    def delete_all(query), do: reply(:delete_all, query)

    defp reply(function, query) do
      send(self(), {:repo, function, query})

      case Process.get({__MODULE__, function}) do
        fun when is_function(fun, 1) -> fun.(query)
        result -> result
      end
    end
  end

  defmodule PostLive do
    @moduledoc false
    def config(:primary_key), do: :id
    def config(:full_text_search), do: nil
    def adapter_config(:schema), do: TestPost
    def adapter_config(:repo), do: FakeRepo
    def adapter_config(:item_query), do: &EctoAdapter.default_item_query/3
  end

  defmodule TestFilter do
    @moduledoc false
    @behaviour Backpex.Filter

    @impl Backpex.Filter
    def label, do: "Test Filter"

    @impl Backpex.Filter
    def can?(_assigns), do: true

    @impl Backpex.Filter
    def condition({field, _config}, value, _assigns), do: {:==, field, value}

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
    def condition({field, _config}, %{"start" => start_val, "end" => end_val}, _assigns) do
      {:and, [{:>=, field, start_val}, {:<=, field, end_val}]}
    end

    @impl Backpex.Filter
    def render(assigns), do: assigns

    @impl Backpex.Filter
    def render_form(assigns), do: assigns
  end

  defmodule ConditionFilter do
    @moduledoc false
    # Returns its value as the condition.
    use Backpex.Filter

    @impl Backpex.Filter
    def label, do: "Condition"

    @impl Backpex.Filter
    def condition(_field, condition, _assigns), do: condition

    @impl Backpex.Filter
    def render(assigns), do: assigns

    @impl Backpex.Filter
    def render_form(assigns), do: assigns
  end

  describe "apply_search/4 (without full text search configured)" do
    test "adds ilike condition for one field" do
      base_query = from(TestUser, as: ^EctoAdapter.name_by_schema(TestUser))

      searchable_fields = [
        {:title, %{module: Backpex.Fields.Text}}
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
        {:title, %{module: Backpex.Fields.Text}},
        {:name, %{module: Backpex.Fields.Text}}
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
        {:title, %{module: Backpex.Fields.Text}}
      ]

      query = EctoAdapter.apply_search(base_query, TestUser, nil, {"", searchable_fields})

      assert query == base_query
    end

    test "uses provided select expression for ilike" do
      base_query = from(TestUser, as: ^EctoAdapter.name_by_schema(TestUser))

      select_expr = dynamic([testuser: u], fragment("UPPER(?)", field(u, ^:name)))

      searchable_fields = [
        {:name_display, %{module: Backpex.Fields.Text, select: select_expr}}
      ]

      query = EctoAdapter.apply_search(base_query, TestUser, nil, {"qux", searchable_fields})

      assert [%{expr: ilike_expr}] = query.wheres
      assert match?({:ilike, _, _}, ilike_expr)

      expr_str = Macro.to_string(ilike_expr)
      assert expr_str =~ "fragment"
      assert expr_str =~ "UPPER("
    end

    test "casts a column that is not a string to text" do
      base_query = from(TestUser, as: ^EctoAdapter.name_by_schema(TestUser))
      searchable_fields = [{:age, %{module: Backpex.Fields.Number}}]

      query = EctoAdapter.apply_search(base_query, TestUser, nil, {"42", searchable_fields})

      assert [%{expr: {:ilike, _meta, [{:fragment, _fragment_meta, parts}, _search]}}] = query.wheres
      assert [raw: "CAST(", expr: _column, raw: " AS TEXT)"] = parts
    end

    test "casts a column of unknown type to text" do
      base_query =
        TestUser
        |> from(as: ^EctoAdapter.name_by_schema(TestUser))
        |> join(:left, [testuser: u], t in "totals", as: :totals, on: t.user_id == u.id)

      # `age` of the custom alias may have another type than `age` of the resource, `total` is no column of it.
      for field <- [
            {:age, %{module: Backpex.Fields.Text, custom_alias: :totals}},
            {:total, %{module: Backpex.Fields.Text}}
          ] do
        query = EctoAdapter.apply_search(base_query, TestUser, nil, {"42", [field]})

        assert [%{expr: {:ilike, _meta, [{:fragment, _fragment_meta, parts}, _search]}}] = query.wheres
        assert [raw: "CAST(", expr: _column, raw: " AS TEXT)"] = parts
      end
    end

    test "uses the search condition of the field module" do
      defmodule ExactSearchField do
        @moduledoc false
        def association?(_field), do: false

        def search_condition(schema_name, field_name, search_string) do
          dynamic([{^schema_name, s}], field(s, ^field_name) == ^String.trim(search_string, "%"))
        end
      end

      base_query = from(TestUser, as: ^EctoAdapter.name_by_schema(TestUser))
      searchable_fields = [{:name, %{module: ExactSearchField}}]

      query = EctoAdapter.apply_search(base_query, TestUser, nil, {"Ann", searchable_fields})

      assert [%{expr: {:==, _meta, _args}, params: [{"Ann", _type}]}] = query.wheres
    end

    test "searches the display field of an association field on the binding of the association" do
      searchable_fields = [{:user, %{module: Backpex.Fields.BelongsTo, display_field: :name}}]

      query =
        TestPost
        |> from(as: :testpost)
        |> join(:left, [testpost: p], u in TestUser, as: :testuser, on: u.id == p.user_id)
        |> EctoAdapter.apply_search(TestPost, nil, {"Ann", searchable_fields})

      assert [%{expr: {:ilike, _meta, [column, _search]}}] = query.wheres
      assert Macro.to_string(column) == "&1.name()"
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

  describe "apply_criteria/4 ordering" do
    defp order_query(order, fields \\ [{:name, %{module: Backpex.Fields.Text}}]) do
      TestUser
      |> from(as: ^EctoAdapter.name_by_schema(TestUser))
      |> EctoAdapter.apply_criteria([order: order], fields, TestUser)
    end

    test "uses the database default for NULL values without a nulls option" do
      for direction <- [:asc, :desc] do
        query = order_query(%{by: :name, direction: direction, field_name: :name})

        assert %{order_bys: [%{expr: [{^direction, order_expression}]}]} = query
        assert Macro.to_string(order_expression) =~ "name"
      end
    end

    test "applies the nulls option to both directions" do
      expected = [
        {:default, :asc, :asc},
        {:default, :desc, :desc},
        {:first, :asc, :asc_nulls_first},
        {:first, :desc, :desc_nulls_first},
        {:last, :asc, :asc_nulls_last},
        {:last, :desc, :desc_nulls_last},
        {:smallest, :asc, :asc_nulls_first},
        {:smallest, :desc, :desc_nulls_last}
      ]

      for {nulls, direction, expected_direction} <- expected do
        query = order_query(%{by: :name, direction: direction, field_name: :name, nulls: nulls})

        assert %{order_bys: [%{expr: [{^expected_direction, _order_expression}]}]} = query
      end
    end

    test "applies ordering with custom select expression" do
      select_expr = dynamic([testuser: u], fragment("UPPER(?)", field(u, ^:name)))
      fields = [{:name, %{module: Backpex.Fields.Text, select: select_expr}}]

      query =
        order_query(%{by: :name, direction: :asc, field_name: :name, nulls: :first}, fields)

      assert %{order_bys: [%{expr: [{:asc_nulls_first, order_expression}]}]} = query

      expr_str = Macro.to_string(order_expression)
      assert expr_str =~ "fragment"
      assert expr_str =~ "UPPER("
    end

    test "orders an association field by its display_field on its custom alias" do
      fields = [
        {:author, %{module: Backpex.Fields.BelongsTo, display_field: :name, custom_alias: :author}}
      ]

      query =
        TestUser
        |> from(as: ^EctoAdapter.name_by_schema(TestUser))
        |> join(:left, [testuser: u], a in TestUser, as: :author, on: a.id == u.id)
        |> EctoAdapter.apply_criteria(
          [order: %{by: :name, direction: :desc, field_name: :author, nulls: :last}],
          fields,
          TestUser
        )

      assert %{order_bys: [%{expr: [{:desc_nulls_last, order_expression}]}]} = query
      assert Macro.to_string(order_expression) == "&1.name()"
    end

    test "orders an association field by its display_field on the binding of the association" do
      fields = [{:user, %{module: Backpex.Fields.BelongsTo, display_field: :name}}]

      query =
        TestPost
        |> from(as: :testpost)
        |> join(:left, [testpost: p], u in TestUser, as: :testuser, on: u.id == p.user_id)
        |> EctoAdapter.apply_criteria([order: %{by: :name, direction: :asc, field_name: :user}], fields, TestPost)

      assert %{order_bys: [%{expr: [{:asc, order_expression}]}]} = query
      assert Macro.to_string(order_expression) == "&1.name()"
    end

    test "applies order by a column that is not a declared field" do
      # :id is not among the declared fields, which is the case for the default
      # init_order of %{by: :id, direction: :asc} on virtually every live resource.
      query = order_query(%{by: :id, direction: :asc, field_name: nil, nulls: :default})

      assert %{order_bys: [%{expr: [{:asc, order_expression}]}]} = query
      assert Macro.to_string(order_expression) =~ "id"
    end

    test "ignores the nulls option for the primary key" do
      fields = [{:id, %{module: Backpex.Fields.Text}}]

      assert %{order_bys: [%{expr: [{:desc, _id}]}]} =
               order_query(%{by: :id, direction: :desc, field_name: :id, nulls: :last}, fields)

      assert %{order_bys: [%{expr: [{:asc, _id}]}]} =
               order_query(%{by: :id, direction: :asc, field_name: nil, nulls: :first})
    end

    test "applies the nulls option to a field with a select expression named like the primary key" do
      select = dynamic([testuser: u], fragment("upper(?)", u.name))
      fields = [{:id, %{module: Backpex.Fields.Text, select: select}}]

      assert %{order_bys: [%{expr: [{:asc_nulls_first, _select}]}]} =
               order_query(%{by: :id, direction: :asc, field_name: :id, nulls: :first}, fields)
    end

    test "applies the nulls option to the primary key of an association" do
      fields = [{:user, %{module: Backpex.Fields.BelongsTo, display_field: :id}}]

      query =
        TestPost
        |> from(as: :testpost)
        |> join(:left, [testpost: p], u in TestUser, as: :testuser, on: u.id == p.user_id)
        |> EctoAdapter.apply_criteria(
          [order: %{by: :id, direction: :asc, field_name: :user, nulls: :first}],
          fields,
          TestPost
        )

      assert %{order_bys: [%{expr: [{:asc_nulls_first, order_expression}]}]} = query
      assert Macro.to_string(order_expression) == "&1.id()"
    end

    test "raises when the order criteria is malformed instead of silently dropping the order" do
      base_query = from(TestUser, as: ^EctoAdapter.name_by_schema(TestUser))

      criteria = [
        order: %{by: :id}
      ]

      assert_raise ArgumentError, ~r/expected order criteria to be a map with the keys :by and :direction/, fn ->
        EctoAdapter.apply_criteria(base_query, criteria, [], TestUser)
      end
    end
  end

  describe "apply_criteria/4 pagination" do
    test "applies limit and offset from pagination" do
      base_query = from(TestUser, as: ^EctoAdapter.name_by_schema(TestUser))

      fields = []

      criteria = [
        pagination: %{page: 3, size: 10}
      ]

      query = EctoAdapter.apply_criteria(base_query, criteria, fields, TestUser)

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

      query = EctoAdapter.apply_criteria(base_query, criteria, fields, TestUser)

      assert %{limit: %{params: [{25, :integer}]}} = query
      assert %{offset: %{params: [{0, :integer}]}} = query
    end

    test "applies simple limit without pagination" do
      base_query = from(TestUser, as: ^EctoAdapter.name_by_schema(TestUser))

      fields = []

      criteria = [
        limit: 5
      ]

      query = EctoAdapter.apply_criteria(base_query, criteria, fields, TestUser)

      assert %{limit: %{params: [{5, :integer}]}} = query
      assert query.offset == nil
    end

    test "returns original query for empty criteria" do
      base_query = from(TestUser, as: ^EctoAdapter.name_by_schema(TestUser))

      query = EctoAdapter.apply_criteria(base_query, [], [], TestUser)

      assert query == base_query
    end

    test "ignores unknown criteria" do
      base_query = from(TestUser, as: ^EctoAdapter.name_by_schema(TestUser))

      fields = []

      criteria = [
        unknown_option: "some_value",
        another_unknown: 123
      ]

      query = EctoAdapter.apply_criteria(base_query, criteria, fields, TestUser)

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

      # Should have 2 where clauses: active == true and age >= 18 and age <= 65
      assert length(query.wheres) == 2
    end

    test "passes assigns to the condition function of the filter" do
      defmodule AssignsCapturingFilter do
        @moduledoc false
        @behaviour Backpex.Filter

        @impl Backpex.Filter
        def label, do: "Assigns Filter"

        @impl Backpex.Filter
        def condition(_field, _value, assigns), do: {:==, :id, Map.get(assigns, :user_id, 0)}

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

    test "turns each condition into a where clause on the schema" do
      expected = [
        {{:==, :age, 1}, "&0.age() == ^0", [1]},
        {{:!=, :age, 1}, "&0.age() != ^0", [1]},
        {{:<, :age, 1}, "&0.age() < ^0", [1]},
        {{:<=, :age, 1}, "&0.age() <= ^0", [1]},
        {{:>, :age, 1}, "&0.age() > ^0", [1]},
        {{:>=, :age, 1}, "&0.age() >= ^0", [1]},
        {{:in, :age, [1, 2]}, "&0.age() in ^0", [[1, 2]]},
        {{:is_nil, :name}, "is_nil(&0.name())", []},
        {{:not, {:==, :active, true}}, "not (&0.active() == ^0)", [true]},
        {{:and, [{:>=, :age, 18}, {:<=, :age, 65}]}, "&0.age() >= ^0 and &0.age() <= ^1", [18, 65]},
        {{:or, [{:==, :name, "Ann"}, {:is_nil, :name}]}, "&0.name() == ^0 or is_nil(&0.name())", ["Ann"]},
        {{:or, []}, "false", []}
      ]

      for {condition, expected_expr, expected_params} <- expected do
        query = filter_query(condition)

        assert [%{expr: expr, params: params}] = query.wheres
        assert Macro.to_string(expr) == expected_expr
        assert Enum.map(params, &elem(&1, 0)) == expected_params
      end

      # Ecto leaves out a `where: true`.
      assert filter_query({:and, []}).wheres == []
    end

    test "casts the values of a condition to the type of the field" do
      assert [%{params: [{"42", {0, :age}}]}] = filter_query({:==, :age, "42"}).wheres
      assert [%{params: [{["1", "2"], {:in, {0, :age}}}]}] = filter_query({:in, :age, ["1", "2"]}).wheres
    end

    test "takes Ecto dynamic expressions as conditions" do
      query = filter_query({:or, [dynamic([testuser: u], u.age > ^18), {:is_nil, :age}]})

      assert [%{expr: expr, params: [{18, _type}]}] = query.wheres
      assert Macro.to_string(expr) == "&0.age() > ^0 or is_nil(&0.age())"
    end

    test "keeps the query without a condition" do
      assert filter_query(nil).wheres == []
    end

    test "raises for nil in the values of an :in condition, also when it is negated" do
      for condition <- [{:in, :age, [1, nil]}, {:not, {:in, :age, [nil]}}] do
        assert_raise ArgumentError, ~r/not to contain nil.*\{:is_nil, :age\}/, fn -> filter_query(condition) end
      end
    end

    test "raises for an unknown condition" do
      assert_raise ArgumentError,
                   ~r/expected a condition such as {:==, :field, value}, got: {:like, :name, "A%"}/,
                   fn ->
                     filter_query({:like, :name, "A%"})
                   end
    end

    test "keeps the items with an associated item through a subquery condition" do
      tagged_posts = from(p in TestPost, join: pt in assoc(p, :post_tags), where: pt.tag_id in ^[1, 2], select: p.id)

      query =
        TestPost
        |> from(as: :testpost)
        |> EctoAdapter.apply_filters(
          %{tags: dynamic([post], post.id in subquery(tagged_posts))},
          [tags: %{module: ConditionFilter}],
          %{}
        )

      assert %{joins: [], distinct: nil, wheres: [where]} = query
      assert %{expr: {:in, _meta, [_id, {:subquery, 0}]}, subqueries: [%Ecto.SubQuery{}]} = where
    end

    defp filter_query(condition) do
      TestUser
      |> from(as: ^EctoAdapter.name_by_schema(TestUser))
      |> EctoAdapter.apply_filters(%{condition: condition}, [condition: %{module: ConditionFilter}], %{})
    end
  end

  describe "association/2" do
    test "returns a belongs_to association" do
      assert EctoAdapter.association(:user, PostLive) ==
               %{field: :user, cardinality: :one, owner_key: :user_id, through: []}
    end

    test "returns the associations a through association goes through" do
      assert %{field: :tags, cardinality: :many, through: [pivot, child]} = EctoAdapter.association(:tags, PostLive)
      assert %{field: :post_tags, cardinality: :many, owner_key: :id} = pivot
      assert %{field: :tag, cardinality: :one, owner_key: :tag_id} = child
    end

    test "returns nil for a field that is not an association" do
      assert EctoAdapter.association(:title, PostLive) == nil
    end
  end

  describe "new_item/2" do
    test "returns a new struct of the schema" do
      assert EctoAdapter.new_item(%{}, PostLive) == %TestPost{}
    end
  end

  describe "list_options/4" do
    @user_field {:user, %{module: Backpex.Fields.BelongsTo, display_field: :name}}

    test "lists the associated items with the options query of the field" do
      Process.put({FakeRepo, :all}, [%TestUser{id: 1}])
      options_query = fn query, assigns -> where(query, [u], u.age > ^assigns.min_age) end
      field = {:user, %{module: Backpex.Fields.BelongsTo, display_field: :name, options_query: options_query}}

      assert EctoAdapter.list_options(field, [], %{min_age: 18}, PostLive) == {:ok, [%TestUser{id: 1}]}

      assert_received {:repo, :all, query}
      assert %{from: %{source: {"users", TestUser}, as: nil}, wheres: [%{params: [{18, _type}]}]} = query
    end

    test "lists the items with the given ids and ignores invalid ids" do
      EctoAdapter.list_options(@user_field, [ids: ["1", 2, "invalid", %{"id" => "3"}]], %{}, PostLive)

      assert_received {:repo, :all, %{wheres: [%{params: [{[1, 2], _type}]}]}}
    end

    test "lists the items with the given ids by the primary key of the associated schema" do
      defmodule TestAuthor do
        use Ecto.Schema

        @primary_key {:uuid, :binary_id, autogenerate: false}
        schema "authors" do
          field :name, :string
        end
      end

      defmodule TestComment do
        use Ecto.Schema

        schema "comments" do
          belongs_to :author, TestAuthor, references: :uuid, type: :binary_id
        end
      end

      defmodule CommentLive do
        @moduledoc false
        def adapter_config(:schema), do: TestComment
        def adapter_config(:repo), do: FakeRepo
      end

      uuid = "5b0a3b7e-0c3d-4b5e-9a3f-2f1d0c6e8a91"
      field = {:author, %{module: Backpex.Fields.BelongsTo, display_field: :name}}

      EctoAdapter.list_options(field, [ids: [uuid, 1]], %{}, CommentLive)

      assert_received {:repo, :all, %{wheres: [%{expr: expr, params: [{[^uuid], _type}]}]}}
      assert Macro.to_string(expr) =~ "&0.uuid()"
    end

    test "limits the ids after the options query, even if it ignores or widens the query it receives" do
      for options_query <- [
            fn _query, _assigns -> from(u in TestUser, where: u.age > 18) end,
            fn query, _assigns -> or_where(query, [u], u.age > 18) end
          ] do
        field = {:user, %{module: Backpex.Fields.BelongsTo, display_field: :name, options_query: options_query}}

        EctoAdapter.list_options(field, [ids: ["1"]], %{}, PostLive)

        assert_received {:repo, :all, %{wheres: wheres}}
        assert %{op: :and, params: [{[1], _type}]} = List.last(wheres)
      end
    end

    test "searches the display field on a named binding, then skips and limits the items" do
      EctoAdapter.list_options(@user_field, [search: "ann", offset: 10, limit: 5], %{}, PostLive)

      assert_received {:repo, :all, query}
      assert %{from: %{as: :testuser}, wheres: [%{expr: {:ilike, _meta, _args}, params: [{"%ann%", _type}]}]} = query
      assert %{offset: %{params: [{10, :integer}]}, limit: %{params: [{5, :integer}]}} = query
    end

    test "searches with the select expression of the field" do
      select = dynamic([testuser: u], fragment("upper(?)", u.name))
      field = {:user, %{module: Backpex.Fields.BelongsTo, display_field: :name, select: select}}

      EctoAdapter.list_options(field, [search: "ann"], %{}, PostLive)

      assert_received {:repo, :all,
                       %{wheres: [%{expr: {:ilike, _meta, [{:fragment, _fragment_meta, _parts}, _search]}}]}}
    end

    test "ignores an empty search" do
      EctoAdapter.list_options(@user_field, [search: " "], %{}, PostLive)

      assert_received {:repo, :all, %{wheres: []}}
    end

    test "lists the items at the end of a through association" do
      field = {:tags, %{module: Backpex.Fields.HasManyThrough, display_field: :name}}

      EctoAdapter.list_options(field, [], %{}, PostLive)

      assert_received {:repo, :all, %{from: %{source: {"tags", TestTag}}}}
    end
  end

  describe "list_options_by_key/4" do
    test "runs every distinct query once" do
      Process.put({FakeRepo, :all}, fn %{wheres: [%{params: [{user_id, _type}]}]} -> [%TestUser{id: user_id}] end)
      options_query = fn query, assigns -> where(query, [u], u.id == ^assigns.user_id) end
      field = {:user, %{module: Backpex.Fields.BelongsTo, display_field: :name, options_query: options_query}}
      assigns_by_key = %{a: %{user_id: 1}, b: %{user_id: 2}, c: %{user_id: 1}}

      assert EctoAdapter.list_options_by_key(field, [], assigns_by_key, PostLive) ==
               {:ok, %{a: [%TestUser{id: 1}], b: [%TestUser{id: 2}], c: [%TestUser{id: 1}]}}

      assert_received {:repo, :all, _query}
      assert_received {:repo, :all, _query}
      refute_received {:repo, :all, _query}
    end
  end

  describe "count_options/4" do
    test "counts the items without offset and limit" do
      Process.put({FakeRepo, :aggregate}, 3)
      field = {:user, %{module: Backpex.Fields.BelongsTo, display_field: :name}}

      assert EctoAdapter.count_options(field, [search: "ann", offset: 10, limit: 5], %{}, PostLive) == {:ok, 3}

      assert_received {:repo, :aggregate, %Ecto.SubQuery{query: query}}
      assert %{offset: nil, limit: nil, wheres: [%{params: [{"%ann%", _type}]}]} = query
    end
  end

  describe "metric/5" do
    test "selects the aggregate of the metric for the items matching the criteria" do
      expected = [
        {:count, "count()"},
        {{:count, :title}, "count(&0.title())"},
        {{:sum, :id}, "sum(&0.id())"},
        {{:avg, :id}, "avg(&0.id())"},
        {{:min, :id}, "min(&0.id())"},
        {{:max, :id}, "max(&0.id())"}
      ]

      for {aggregate, expected_select} <- expected do
        Process.put({FakeRepo, :one}, 3)

        assert {:ok, 3} = metric(%{module: Value, aggregate: aggregate})
        assert_received {:repo, :one, query}
        assert %{preloads: [], group_bys: [], joins: [%{as: :testuser}], wheres: [_search]} = query
        assert Macro.to_string(query.select.expr) == expected_select
      end
    end

    test "limits the items with the where condition of the metric" do
      metric(%{module: Value, aggregate: :count, where: {:==, :title, "Hello"}})

      assert_received {:repo, :one, %{wheres: [_search, %{expr: expr, params: [{"Hello", _type}]}]}}
      assert Macro.to_string(expr) == "&0.title() == ^0"
    end

    test "selects the select expression of the metric instead of an aggregate" do
      metric(%{module: Value, select: dynamic([p], count(p.id))})

      assert_received {:repo, :one, query}
      assert Macro.to_string(query.select.expr) == "count(&0.id())"
    end

    test "ignores the order, the pagination and the limit" do
      criteria = [
        order: %{by: :title, direction: :asc, field_name: :title},
        pagination: %{page: 3, size: 10},
        limit: 5
      ]

      metric(%{module: Value, aggregate: {:sum, :id}}, criteria)

      assert_received {:repo, :one, query}
      assert %{order_bys: [], limit: nil, offset: nil, wheres: [_search]} = query
    end

    test "drops an order of the item query from the aggregate" do
      defmodule OrderedPostLive do
        @moduledoc false
        def config(:primary_key), do: :id
        def config(:full_text_search), do: nil
        def adapter_config(:schema), do: TestPost
        def adapter_config(:repo), do: FakeRepo
        def adapter_config(:item_query), do: fn query, _live_action, _assigns -> order_by(query, :title) end
      end

      criteria = [search: {"", []}]

      EctoAdapter.metric(%{module: Value, aggregate: :count}, criteria, [], %{live_action: :index}, OrderedPostLive)

      assert_received {:repo, :one, %{order_bys: []}}
    end

    test "raises for a metric without an aggregate" do
      assert_raise ArgumentError, ~r/expected the metric to have an :aggregate option/, fn ->
        metric(%{module: Value})
      end

      assert_raise ArgumentError, ~r/expected an aggregate such as :count or {:sum, :field}, got: :sum/, fn ->
        metric(%{module: Value, aggregate: :sum})
      end
    end

    defp metric(metric, criteria \\ []) do
      fields = [user: %{module: Backpex.Fields.BelongsTo, display_field: :name}]
      criteria = [search: {"Ann", [title: %{module: Backpex.Fields.Text}]}] ++ criteria

      EctoAdapter.metric(metric, criteria, fields, %{live_action: :index}, PostLive)
    end
  end

  describe "field_config_schema/0" do
    test "adds the select and custom_alias options to fields" do
      assert [:select, :custom_alias] = Keyword.keys(EctoAdapter.field_config_schema())
    end
  end

  describe "put_assoc/4" do
    test "puts the associated items into the changeset" do
      changeset = Ecto.Changeset.change(%TestPost{})

      assert %{changes: %{post_tags: [%Ecto.Changeset{action: :insert}]}} =
               EctoAdapter.put_assoc(changeset, :post_tags, [%TestPostTag{tag_id: 1}], PostLive)
    end
  end

  describe "delete_all/2" do
    test "returns a foreign key violation instead of raising it" do
      Process.put({FakeRepo, :delete_all}, fn _query -> raise Postgrex.Error, postgres: %{code: "23503"} end)

      assert EctoAdapter.delete_all([%TestPost{id: 1}], PostLive) == {:error, :foreign_key_violation}
    end

    test "raises any other error" do
      Process.put({FakeRepo, :delete_all}, fn _query ->
        raise Postgrex.Error, postgres: %{code: "23505", severity: "ERROR", message: "duplicate key"}
      end)

      assert_raise Postgrex.Error, fn -> EctoAdapter.delete_all([%TestPost{id: 1}], PostLive) end
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
