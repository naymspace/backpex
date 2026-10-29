defmodule Backpex.Adapters.EctoTest do
  use ExUnit.Case, async: true

  import Backpex.Expr, only: [expr: 1]
  import Ecto.Query

  alias Backpex.Adapters.Ecto, as: EctoAdapter
  alias Backpex.Expr
  alias Backpex.Metrics.Value
  alias Backpex.Query
  alias Backpex.Resource

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

  defmodule FakeLiveResource do
    @moduledoc false
    # Defines the `config/1` and `adapter_config/1` of a LiveResource of the `:schema` that reads with the `FakeRepo`.
    # Takes the `:full_text_search` and an overridable `item_query/3`.
    defmacro __using__(opts) do
      quote do
        @schema Keyword.fetch!(unquote(opts), :schema)
        @full_text_search Keyword.get(unquote(opts), :full_text_search)

        def config(:primary_key), do: :id
        def config(:full_text_search), do: @full_text_search
        def config(:order_nulls), do: nil
        def config(:adapter), do: Backpex.Adapters.Ecto
        def adapter_config(:schema), do: @schema
        def adapter_config(:repo), do: Backpex.Adapters.EctoTest.FakeRepo
        def adapter_config(:item_query), do: &__MODULE__.item_query/3

        def item_query(query, _live_action, _assigns), do: query

        defoverridable item_query: 3
      end
    end
  end

  defmodule PostLive do
    @moduledoc false
    use FakeLiveResource, schema: Backpex.Adapters.EctoTest.TestPost
  end

  defmodule UserLive do
    @moduledoc false
    use FakeLiveResource, schema: Backpex.Adapters.EctoTest.TestUser
  end

  defmodule FullTextUserLive do
    @moduledoc false
    use FakeLiveResource, schema: Backpex.Adapters.EctoTest.TestUser, full_text_search: :title
  end

  defmodule TotalsUserLive do
    @moduledoc false
    use FakeLiveResource, schema: Backpex.Adapters.EctoTest.TestUser

    # Joins a table that the schema of the resource doesn't describe.
    def item_query(query, _live_action, _assigns) do
      join(query, :left, [testuser: u], t in "totals", as: :totals, on: t.user_id == u.id)
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
    def condition({field, _config}, value, _assigns), do: expr(ref(^field) == ^value)

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
      expr(ref(^field) >= ^start_val and ref(^field) <= ^end_val)
    end

    @impl Backpex.Filter
    def render(assigns), do: assigns

    @impl Backpex.Filter
    def render_form(assigns), do: assigns
  end

  # The query of the resource without search, filters, sorts and pagination.
  defp base_query(schema \\ TestUser), do: from(schema, as: ^EctoAdapter.name_by_schema(schema))

  describe "read/1 search (without full text search configured)" do
    test "adds ilike condition for one field" do
      query = search_query("foo", title: %{module: Backpex.Fields.Text})

      assert [%{expr: ilike_expr}] = query.wheres
      assert match?({:ilike, _, _}, ilike_expr)

      expr_str = Macro.to_string(ilike_expr)
      assert expr_str =~ "title"
    end

    test "chains ilike conditions with OR for multiple fields" do
      query = search_query("bar", title: %{module: Backpex.Fields.Text}, name: %{module: Backpex.Fields.Text})

      assert [%{expr: or_expr}] = query.wheres
      assert match?({:or, _, _}, or_expr)

      expr_str = Macro.to_string(or_expr)
      assert expr_str =~ "title"
      assert expr_str =~ "name"
    end

    test "returns original query when no searchable fields provided" do
      assert search_query("baz", []) == base_query()
    end

    test "returns original query when empty search string provided" do
      assert search_query("", title: %{module: Backpex.Fields.Text}) == base_query()
    end

    test "uses provided select expression for ilike" do
      select_expr = dynamic([testuser: u], fragment("UPPER(?)", field(u, ^:name)))

      query = search_query("qux", name_display: %{module: Backpex.Fields.Text, select: select_expr})

      assert [%{expr: ilike_expr}] = query.wheres
      assert match?({:ilike, _, _}, ilike_expr)

      expr_str = Macro.to_string(ilike_expr)
      assert expr_str =~ "fragment"
      assert expr_str =~ "UPPER("
    end

    test "casts a column that is not a string to text" do
      query = search_query("42", age: %{module: Backpex.Fields.Number})

      assert [%{expr: {:ilike, _meta, [{:fragment, _fragment_meta, parts}, _search]}}] = query.wheres
      assert [raw: "CAST(", expr: _column, raw: " AS TEXT)"] = parts
    end

    test "casts a column of unknown type to text" do
      # `age` of the custom alias may have another type than `age` of the resource, `total` is no column of it.
      for field <- [
            {:age, %{module: Backpex.Fields.Text, custom_alias: :totals}},
            {:total, %{module: Backpex.Fields.Text}}
          ] do
        query = search_query("42", [field], TotalsUserLive)

        assert [%{expr: {:ilike, _meta, [{:fragment, _fragment_meta, parts}, _search]}}] = query.wheres
        assert [raw: "CAST(", expr: _column, raw: " AS TEXT)"] = parts
      end
    end

    test "uses the search condition of the field module" do
      defmodule ExactSearchField do
        @moduledoc false
        def association?(_field), do: false

        def display_field({name, _field_options}), do: name

        def search_condition(schema_name, field_name, search_string) do
          dynamic([{^schema_name, s}], field(s, ^field_name) == ^String.trim(search_string, "%"))
        end
      end

      query = search_query("Ann", name: %{module: ExactSearchField})

      assert [%{expr: {:==, _meta, _args}, params: [{"Ann", _type}]}] = query.wheres
    end

    test "searches the display field of an association field on the binding of the association" do
      query = search_query("Ann", [user: %{module: Backpex.Fields.BelongsTo, display_field: :name}], PostLive)

      assert [%{as: :testuser}] = query.joins
      assert [%{expr: {:ilike, _meta, [column, _search]}}] = query.wheres
      assert Macro.to_string(column) == "&1.name()"
    end
  end

  describe "read/1 search (with full text search configured)" do
    test "returns original query on empty search string" do
      assert search_query("", [], FullTextUserLive) == base_query()
    end

    test "adds tsquery fragment for non-empty search string" do
      query = search_query("hello world", [], FullTextUserLive)

      assert [%{expr: fragment_expr}] = query.wheres
      assert match?({:fragment, _, _}, fragment_expr)

      expr_str = Macro.to_string(fragment_expr)
      assert expr_str =~ "websearch_to_tsquery"
      assert expr_str =~ "@@"
      assert expr_str =~ "title"
    end
  end

  # Searches the fields like the index view, see `Backpex.LiveResource.filter_query/2`.
  defp search_query(search, fields, live_resource \\ UserLive) do
    fields
    |> Backpex.Resource.items_query(%{live_action: :index}, live_resource)
    |> Query.search(search, Enum.map(fields, &Backpex.LiveResource.field_ref/1))
    |> EctoAdapter.ecto_query()
  end

  describe "read/1 sorting" do
    test "uses the database default for NULL values without a nulls option" do
      for direction <- [:asc, :desc] do
        query = index_query([name: %{module: Backpex.Fields.Text}], order_by: :name, order_direction: direction)

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
        fields = [name: %{module: Backpex.Fields.Text, order_nulls: nulls}]
        query = index_query(fields, order_by: :name, order_direction: direction)

        assert %{order_bys: [%{expr: [{^expected_direction, _order_expression}]}]} = query
      end
    end

    test "applies ordering with custom select expression" do
      select_expr = dynamic([testuser: u], fragment("UPPER(?)", field(u, ^:name)))
      fields = [name: %{module: Backpex.Fields.Text, select: select_expr, order_nulls: :first}]

      query = index_query(fields, order_by: :name, order_direction: :asc)

      assert %{order_bys: [%{expr: [{:asc_nulls_first, order_expression}]}]} = query

      expr_str = Macro.to_string(order_expression)
      assert expr_str =~ "fragment"
      assert expr_str =~ "UPPER("
    end

    test "orders an association field by its display_field on its custom alias" do
      fields = [
        user: %{module: Backpex.Fields.BelongsTo, display_field: :name, custom_alias: :author, order_nulls: :last}
      ]

      query = index_query(fields, [order_by: :user, order_direction: :desc], PostLive)

      assert [%{as: :author}] = query.joins
      assert %{order_bys: [%{expr: [{:desc_nulls_last, order_expression}]}]} = query
      assert Macro.to_string(order_expression) == "&1.name()"
    end

    test "orders an association field by its display_field on the binding of the association" do
      fields = [user: %{module: Backpex.Fields.BelongsTo, display_field: :name}]

      query = index_query(fields, [order_by: :user, order_direction: :asc], PostLive)

      assert %{order_bys: [%{expr: [{:asc, order_expression}]}]} = query
      assert Macro.to_string(order_expression) == "&1.name()"
    end

    test "applies order by a column that is not a declared field" do
      # :id is not among the declared fields, which is the case for the default
      # init_order of %{by: :id, direction: :asc} on virtually every live resource.
      query = index_query([name: %{module: Backpex.Fields.Text}], order_by: :id, order_direction: :asc)

      assert %{order_bys: [%{expr: [{:asc, order_expression}]}]} = query
      assert Macro.to_string(order_expression) =~ "id"
    end

    test "ignores the nulls option for the primary key" do
      fields = [id: %{module: Backpex.Fields.Text, order_nulls: :last}]

      assert %{order_bys: [%{expr: [{:desc, _id}]}]} = index_query(fields, order_by: :id, order_direction: :desc)
      assert %{order_bys: [%{expr: [{:asc, _id}]}]} = sort_query(id: :asc_nulls_first)
    end

    test "applies the nulls option to a field with a select expression named like the primary key" do
      select = dynamic([testuser: u], fragment("upper(?)", u.name))
      fields = [id: %{module: Backpex.Fields.Text, select: select, order_nulls: :first}]

      assert %{order_bys: [%{expr: [{:asc_nulls_first, _select}]}]} =
               index_query(fields, order_by: :id, order_direction: :asc)
    end

    test "applies the nulls option to the primary key of an association" do
      fields = [user: %{module: Backpex.Fields.BelongsTo, display_field: :id, order_nulls: :first}]

      query = index_query(fields, [order_by: :user, order_direction: :asc], PostLive)

      assert %{order_bys: [%{expr: [{:asc_nulls_first, order_expression}]}]} = query
      assert Macro.to_string(order_expression) == "&1.id()"
    end

    test "raises when the sort is malformed instead of silently dropping the sort" do
      assert_raise ArgumentError, ~r/expected a field and a direction such as {:title, :asc}, got: :id/, fn ->
        sort_query([:id])
      end
    end

    test "applies the sorts of the query instead of its default sorts" do
      assert %{order_bys: [%{expr: [{:desc, name}]}]} =
               UserLive |> Query.new() |> Query.default_sort(id: :asc) |> Query.sort(name: :desc) |> ecto_query()

      assert Macro.to_string(name) == "&0.name()"
    end
  end

  describe "read/1 pagination" do
    test "applies limit and offset from pagination" do
      query = index_query([], page: 3, per_page: 10)

      # Limit and offset are stored as pinned params
      assert %{limit: %{params: [{10, :integer}]}} = query
      assert %{offset: %{params: [{20, :integer}]}} = query
    end

    test "applies first page correctly with zero offset" do
      query = index_query([], page: 1, per_page: 25)

      assert %{limit: %{params: [{25, :integer}]}} = query
      assert %{offset: %{params: [{0, :integer}]}} = query
    end

    test "applies simple limit without pagination" do
      query = UserLive |> Query.new() |> Query.limit(5) |> ecto_query()

      assert %{limit: %{params: [{5, :integer}]}} = query
      assert query.offset == nil
    end

    test "returns original query for an empty query" do
      assert UserLive |> Query.new() |> ecto_query() == base_query()
    end
  end

  # The query of the index view, see `Backpex.LiveResource.index_query/2`.
  defp index_query(fields, query_options, live_resource \\ UserLive) do
    query_options = Map.merge(%{order_by: :id, order_direction: :asc, page: 1, per_page: 15}, Map.new(query_options))

    ecto_query(
      Backpex.LiveResource.index_query(
        %{
          live_resource: live_resource,
          live_action: :index,
          fields: fields,
          filters: [],
          filter_values: %{},
          init_order: %{by: :id, direction: :asc},
          query_options: query_options
        },
        fields
      )
    )
  end

  defp sort_query(sorts), do: UserLive |> Query.new() |> Query.sort(sorts) |> ecto_query()

  defp ecto_query(query), do: EctoAdapter.ecto_query(query)

  describe "read/1 filters" do
    test "returns original query when filter_values is empty" do
      assert filter_values_query(%{}, []) == base_query()
    end

    test "applies single filter correctly" do
      query = filter_values_query(%{active: true}, active: %{module: TestFilter})

      assert [%{expr: where_expr}] = query.wheres
      assert match?({:==, _, _}, where_expr)

      expr_str = Macro.to_string(where_expr)
      assert expr_str =~ "active"
    end

    test "applies multiple filters with AND logic" do
      filter_values = %{
        active: true,
        age: %{"start" => 18, "end" => 65}
      }

      filter_configs = [
        active: %{module: TestFilter},
        age: %{module: TestRangeFilter}
      ]

      query = filter_values_query(filter_values, filter_configs)

      # One where clause: active == true and (age >= 18 and age <= 65)
      assert [%{expr: {:and, _meta, _args} = where_expr, params: params}] = query.wheres
      assert Macro.to_string(where_expr) =~ "active"
      assert Macro.to_string(where_expr) =~ "age"
      assert Enum.map(params, &elem(&1, 0)) == [true, 18, 65]
    end

    test "passes assigns to the condition function of the filter" do
      defmodule AssignsCapturingFilter do
        @moduledoc false
        @behaviour Backpex.Filter

        @impl Backpex.Filter
        def label, do: "Assigns Filter"

        @impl Backpex.Filter
        def condition(_field, _value, assigns), do: expr(id == ^Map.get(assigns, :user_id, 0))

        @impl Backpex.Filter
        def render(assigns), do: assigns

        @impl Backpex.Filter
        def render_form(assigns), do: assigns

        @impl Backpex.Filter
        def can?(_assigns), do: true
      end

      filter_values = %{owner: "any"}
      filter_configs = [owner: %{module: AssignsCapturingFilter}]

      query = filter_values_query(filter_values, filter_configs, %{user_id: 42})

      assert [%{expr: _where_expr, params: params}] = query.wheres
      # The params should contain the user_id from assigns
      assert Enum.any?(params, fn {val, _type} -> val == 42 end)
    end

    test "skips filters without matching config" do
      query = filter_values_query(%{active: true, unknown: "value"}, active: %{module: TestFilter})

      # Only one filter applied (active), unknown is skipped
      assert [%{expr: where_expr}] = query.wheres
      assert match?({:==, _, _}, where_expr)
    end

    test "turns each expression into a where clause on the schema" do
      expected = [
        {expr(age == 1), "&0.age() == ^0", [1]},
        {expr(age != 1), "&0.age() != ^0", [1]},
        {expr(age < 1), "&0.age() < ^0", [1]},
        {expr(age <= 1), "&0.age() <= ^0", [1]},
        {expr(age > 1), "&0.age() > ^0", [1]},
        {expr(age >= 1), "&0.age() >= ^0", [1]},
        {expr(1 < age), "&0.age() > ^0", [1]},
        {expr(age in [1, 2]), "&0.age() in ^0", [[1, 2]]},
        {expr(is_nil(name)), "is_nil(&0.name())", []},
        {expr(not (active == true)), "not (&0.active() == ^0)", [true]},
        {expr(age >= 18 and age <= 65), "&0.age() >= ^0 and &0.age() <= ^1", [18, 65]},
        {expr(name == "Ann" or is_nil(name)), "&0.name() == ^0 or is_nil(&0.name())", ["Ann"]},
        {expr(title == name), "&0.title() == &0.name()", []},
        {expr(contains(name, "a%")), "like(&0.name(), ^0)", ["%a\\%%"]},
        {expr(starts_with(name, "A", ignore_case: true)), "ilike(&0.name(), ^0)", ["A%"]},
        {[name: "Ann"], "&0.name() == ^0", ["Ann"]},
        {%Expr.Call{name: :or, args: []}, "false", []}
      ]

      for {condition, expected_expr, expected_params} <- expected do
        query = filter_query(condition)

        assert [%{expr: expr, params: params}] = query.wheres
        assert Macro.to_string(expr) == expected_expr
        assert Enum.map(params, &elem(&1, 0)) == expected_params
      end

      # Ecto leaves out a `where: true`.
      assert filter_query(%Expr.Call{name: :and, args: []}).wheres == []
    end

    test "casts the values of an expression to the type of the field" do
      assert [%{params: [{42, {0, :age}}]}] = filter_query(expr(age == "42")).wheres
      assert [%{params: [{[1, 2], {:in, {0, :age}}}]}] = filter_query(expr(age in ["1", "2"])).wheres
    end

    test "takes native Ecto dynamic expressions" do
      native = Expr.native(EctoAdapter, dynamic([testuser: u], u.age > ^18))
      query = filter_query(Expr.any([native, expr(is_nil(age))]))

      assert [%{expr: expr, params: [{18, _type}]}] = query.wheres
      assert Macro.to_string(expr) == "&0.age() > ^0 or is_nil(&0.age())"
    end

    test "keeps the query without an expression" do
      assert filter_query(nil).wheres == []
    end

    test "raises for nil in the values of in, also when it is negated" do
      for condition <- [expr(age in [1, nil]), expr(age not in [nil])] do
        assert_raise ArgumentError, ~r/not to contain nil.*is_nil\(age\)/, fn -> filter_query(condition) end
      end
    end

    test "raises for the condition tuples of earlier versions and for unsupported expressions" do
      assert_raise ArgumentError,
                   ~r/expected an expression such as expr\(published == true\), got: {:==, :name, "A"}/,
                   fn ->
                     filter_query({:==, :name, "A"})
                   end

      assert_raise ArgumentError, ~r/unsupported expression/, fn ->
        filter_query(%Expr.Call{name: :like, args: [Expr.ref(:name), "A%"]})
      end
    end

    test "raises with a hint to wrap an Ecto dynamic expression" do
      assert_raise ArgumentError, ~r/Backpex.Expr.native\(Backpex.Adapters.Ecto, dynamic/, fn ->
        filter_query(dynamic([testuser: u], u.age > 18))
      end
    end

    test "keeps the items with a matching associated item through a subquery, without a join" do
      query = filter_query(expr(exists(tags, id in [1, 2])), PostLive)

      assert %{joins: [], distinct: nil, wheres: [where]} = query
      assert %{expr: {:in, _meta, [_id, {:subquery, 0}]}, subqueries: [%Ecto.SubQuery{query: subquery}]} = where
      assert [%{as: :backpex_tags}] = subquery.joins
    end

    test "joins the relationships of a path to one item" do
      query = filter_query(expr(user.name == "Ann"), PostLive)

      assert [%{as: :backpex_user, qual: :left}] = query.joins
      assert [%{expr: expr, params: [{"Ann", {1, :name}}]}] = query.wheres
      assert Macro.to_string(expr) == "&1.name() == ^0"
    end

    defp filter_query(condition, live_resource \\ UserLive) do
      live_resource |> Query.new() |> Query.filter(condition) |> ecto_query()
    end

    # Applies the filter values like the index view, see `Backpex.LiveResource.filter_query/2`.
    defp filter_values_query(filter_values, filters, assigns \\ %{}) do
      assigns =
        Map.merge(assigns, %{
          live_resource: UserLive,
          fields: [],
          filters: filters,
          filter_values: filter_values,
          query_options: %{}
        })

      UserLive
      |> Query.new(%{assigns: assigns})
      |> Backpex.LiveResource.filter_query(assigns)
      |> ecto_query()
    end
  end

  describe "describe/2" do
    test "describes the primary key, the fields with their types and the associations of the schema" do
      assert %Backpex.Adapter.Description{primary_key: [:id], fields: fields, relationships: relationships} =
               EctoAdapter.describe([], PostLive)

      assert fields.title == %{type: :string, primitive: :string}
      assert fields.user_id == %{type: :id, primitive: :id}
      assert relationships.user == %{field: :user, cardinality: :one, owner_key: :user_id, through: []}
      assert Map.keys(relationships) |> Enum.sort() == [:post_tags, :tags, :user]
    end

    test "describes the associations a through association goes through" do
      %{relationships: %{tags: tags}} = EctoAdapter.describe([], PostLive)

      assert %{field: :tags, cardinality: :many, through: [pivot, child]} = tags
      assert %{field: :post_tags, cardinality: :many, owner_key: :id} = pivot
      assert %{field: :tag, cardinality: :one, owner_key: :tag_id} = child
    end

    test "describes the schema at the end of a path, also through a through association" do
      assert %{fields: %{age: %{type: :integer}}} = EctoAdapter.describe([:user], PostLive)
      assert %{fields: %{name: %{type: :string}}, relationships: %{}} = EctoAdapter.describe([:tags], PostLive)
      assert EctoAdapter.describe([:title], PostLive) == nil
      assert EctoAdapter.describe([:user, :unknown], PostLive) == nil
    end
  end

  describe "new_item/2" do
    test "returns a new struct of the schema" do
      assert EctoAdapter.new_item(%{}, PostLive) == %TestPost{}
    end
  end

  describe "options" do
    @user_field {:user, %{module: Backpex.Fields.BelongsTo, display_field: :name}}

    test "lists the associated items with the options query of the field" do
      Process.put({FakeRepo, :all}, [%TestUser{id: 1}])
      options_query = fn query, assigns -> where(query, [u], u.age > ^assigns.min_age) end
      field = {:user, %{module: Backpex.Fields.BelongsTo, display_field: :name, options_query: options_query}}

      assert Resource.list_options(field, [], %{min_age: 18}, PostLive) == {:ok, [%TestUser{id: 1}]}

      assert_received {:repo, :all, query}
      assert %{from: %{source: {"users", TestUser}, as: nil}, wheres: [%{params: [{18, _type}]}]} = query
    end

    test "lists the items with the given ids and ignores invalid ids" do
      Resource.list_options(@user_field, [ids: ["1", 2, "invalid", %{"id" => "3"}]], %{}, PostLive)

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
        use FakeLiveResource, schema: Backpex.Adapters.EctoTest.TestComment
      end

      uuid = "5b0a3b7e-0c3d-4b5e-9a3f-2f1d0c6e8a91"
      field = {:author, %{module: Backpex.Fields.BelongsTo, display_field: :name}}

      Resource.list_options(field, [ids: [uuid, 1, "invalid"]], %{}, CommentLive)

      assert_received {:repo, :all, %{wheres: [%{expr: expr, params: [{[^uuid], _type}]}]}}
      assert Macro.to_string(expr) =~ "&0.uuid()"
    end

    test "limits the ids after the options query, even if it ignores or widens the query it receives" do
      for options_query <- [
            fn _query, _assigns -> from(u in TestUser, where: u.age > 18) end,
            fn query, _assigns -> or_where(query, [u], u.age > 18) end
          ] do
        field = {:user, %{module: Backpex.Fields.BelongsTo, display_field: :name, options_query: options_query}}

        Resource.list_options(field, [ids: ["1"]], %{}, PostLive)

        assert_received {:repo, :all, %{wheres: wheres}}
        assert %{op: :and, params: [{[1], _type}]} = List.last(wheres)
      end
    end

    test "searches the display field, then skips and limits the items" do
      Resource.list_options(@user_field, [search: "ann", offset: 10, limit: 5], %{}, PostLive)

      assert_received {:repo, :all, query}
      assert %{wheres: [%{expr: {:ilike, _meta, [column, _search]}, params: [{"%ann%", _type}]}]} = query
      assert Macro.to_string(column) == "&0.name()"
      assert %{offset: %{params: [{10, :integer}]}, limit: %{params: [{5, :integer}]}} = query
    end

    test "searches with the select expression of the field" do
      select = dynamic([testuser: u], fragment("upper(?)", u.name))
      field = {:user, %{module: Backpex.Fields.BelongsTo, display_field: :name, select: select}}

      Resource.list_options(field, [search: "ann"], %{}, PostLive)

      assert_received {:repo, :all,
                       %{
                         from: %{as: :testuser},
                         wheres: [%{expr: {:ilike, _meta, [{:fragment, _fragment_meta, _parts}, _search]}}]
                       }}
    end

    test "leaves the binding to the options query of a field with a select expression unless it searches" do
      select = dynamic([testuser: u], fragment("upper(?)", u.name))
      options_query = fn query, _assigns -> from(u in query, as: :testuser, where: u.age > 18) end

      field =
        {:user, %{module: Backpex.Fields.BelongsTo, display_field: :name, select: select, options_query: options_query}}

      Resource.list_options(field, [], %{}, PostLive)

      assert_received {:repo, :all, %{from: %{as: :testuser}, wheres: [_age]}}
    end

    test "changes the key of the options with the assigns the options query depends on" do
      options_query = fn query, assigns -> where(query, [u], u.age > ^assigns.min_age) end
      field = {:user, %{module: Backpex.Fields.BelongsTo, display_field: :name, options_query: options_query}}

      assert Resource.options_key(field, %{min_age: 18, other: 1}, PostLive) ==
               Resource.options_key(field, %{min_age: 18, other: 2}, PostLive)

      refute Resource.options_key(field, %{min_age: 18}, PostLive) ==
               Resource.options_key(field, %{min_age: 21}, PostLive)
    end

    test "ignores an empty search" do
      Resource.list_options(@user_field, [search: " "], %{}, PostLive)

      assert_received {:repo, :all, %{wheres: []}}
    end

    test "lists the items at the end of a through association" do
      field = {:tags, %{module: Backpex.Fields.HasManyThrough, display_field: :name}}

      Resource.list_options(field, [], %{}, PostLive)

      assert_received {:repo, :all, %{from: %{source: {"tags", TestTag}}}}
    end

    test "runs every distinct query of list_options_by_key/4 once" do
      Process.put({FakeRepo, :all}, fn %{wheres: [%{params: [{user_id, _type}]}]} -> [%TestUser{id: user_id}] end)
      options_query = fn query, assigns -> where(query, [u], u.id == ^assigns.user_id) end
      field = {:user, %{module: Backpex.Fields.BelongsTo, display_field: :name, options_query: options_query}}
      assigns_by_key = %{a: %{user_id: 1}, b: %{user_id: 2}, c: %{user_id: 1}}

      assert Resource.list_options_by_key(field, [], assigns_by_key, PostLive) ==
               {:ok, %{a: [%TestUser{id: 1}], b: [%TestUser{id: 2}], c: [%TestUser{id: 1}]}}

      assert_received {:repo, :all, _query}
      assert_received {:repo, :all, _query}
      refute_received {:repo, :all, _query}
    end

    test "counts the items of count_options/4 without offset and limit" do
      Process.put({FakeRepo, :aggregate}, 3)

      assert Resource.count_options(@user_field, [search: "ann", offset: 10, limit: 5], %{}, PostLive) == {:ok, 3}

      assert_received {:repo, :aggregate, %Ecto.SubQuery{query: query}}
      assert %{offset: nil, limit: nil, wheres: [%{params: [{"%ann%", _type}]}]} = query
    end
  end

  describe "aggregate/1" do
    test "selects the aggregate of the metric for the items matching the query" do
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

        assert %{value: 3} = metric(%{module: Value, aggregate: aggregate})
        assert_received {:repo, :one, query}
        assert %{preloads: [], group_bys: [], joins: [%{as: :testuser}], wheres: [_search]} = query
        assert Macro.to_string(query.select.expr) == expected_select
      end
    end

    test "limits the items with the where condition of the metric" do
      metric(%{module: Value, aggregate: :count, where: expr(title == "Hello")})

      assert_received {:repo, :one, %{wheres: [_search, %{expr: expr, params: [{"Hello", _type}]}]}}
      assert Macro.to_string(expr) == "&0.title() == ^0"
    end

    test "selects the select expression of the metric instead of an aggregate" do
      metric(%{module: Value, select: dynamic([p], count(p.id))})

      assert_received {:repo, :one, query}
      assert Macro.to_string(query.select.expr) == "count(&0.id())"
    end

    test "ignores the sort, the offset and the limit" do
      metric(%{module: Value, aggregate: {:sum, :id}}, fn query ->
        query |> Query.sort(title: :asc) |> Query.offset(20) |> Query.limit(10)
      end)

      assert_received {:repo, :one, query}
      assert %{order_bys: [], limit: nil, offset: nil, wheres: [_search]} = query
    end

    test "drops an order of the item query from the aggregate" do
      defmodule OrderedPostLive do
        @moduledoc false
        use FakeLiveResource, schema: Backpex.Adapters.EctoTest.TestPost

        def item_query(query, _live_action, _assigns), do: order_by(query, :title)
      end

      query = Query.new(OrderedPostLive, %{assigns: %{live_action: :index}})

      Resource.metrics([value: %{module: Value, aggregate: :count}], query, %{live_action: :index})

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

    # The data of the metric for the items of the resource that match a search, see `Backpex.Resource.metrics/3`.
    defp metric(metric, fun \\ & &1) do
      fields = [title: %{module: Backpex.Fields.Text}, user: %{module: Backpex.Fields.BelongsTo, display_field: :name}]
      assigns = %{live_action: :index}

      query =
        fields
        |> Resource.items_query(assigns, PostLive)
        |> Query.search("Ann", [:title])
        |> fun.()

      Resource.metrics([value: metric], query, assigns)
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
