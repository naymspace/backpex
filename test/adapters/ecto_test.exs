defmodule Backpex.Adapters.EctoTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  alias Backpex.Adapters.Ecto, as: EctoAdapter

  defmodule TestUser do
    use Ecto.Schema

    @primary_key {:id, :id, autogenerate: false}
    schema "users" do
      field :title, :string
      field :name, :string
    end
  end

  defmodule TestUUID do
    use Ecto.Schema

    @primary_key {:id, :binary_id, autogenerate: false}
    schema "uuids" do
      field :title, :string
    end
  end

  defmodule CaptureRepo do
    def one(query) do
      send(self(), {:repo_one, query})
      nil
    end
  end

  defmodule TestLiveResource do
    def adapter_config(:repo), do: Backpex.Adapters.EctoTest.CaptureRepo
    def adapter_config(:schema), do: Backpex.Adapters.EctoTest.TestUser
    def adapter_config(:item_query), do: &Backpex.Adapters.Ecto.default_item_query/3
    def config(:primary_key), do: :id
    def validated_fields, do: []
  end

  describe "apply_search/4 (without full text search configured)" do
    test "adds ilike condition for one field" do
      base_query = from(TestUser, as: ^EctoAdapter.name_by_schema(TestUser))

      searchable_fields = [
        {:title, %{module: Backpex.Fields.Text, queryable: TestUser}}
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
        {:title, %{module: Backpex.Fields.Text, queryable: TestUser}},
        {:name, %{module: Backpex.Fields.Text, queryable: TestUser}}
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
        {:title, %{module: Backpex.Fields.Text, queryable: TestUser}}
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
  end

  describe "get/3" do
    test "builds query with distinct and id filter and calls repo.one" do
      live_resource = Backpex.Adapters.EctoTest.TestLiveResource
      assigns = %{live_resource: live_resource, live_action: :show}

      assert {:ok, nil} = EctoAdapter.get(123, assigns, live_resource)

      assert_received {:repo_one, %Ecto.Query{} = query}

      # distinct on id
      assert %Ecto.Query{distinct: %Ecto.Query.ByExpr{expr: expr}} = query
      assert Macro.to_string(expr) =~ "id"

      # where equals on id
      assert [%{expr: where_expr}] = query.wheres
      assert match?({:==, _, _}, where_expr)
      assert Macro.to_string(where_expr) =~ "id"
    end

    test "raises on invalid id casting for :id primary key" do
      live_resource = Backpex.Adapters.EctoTest.TestLiveResource
      assigns = %{live_resource: live_resource, live_action: :show}

      assert_raise Ecto.NoResultsError, fn ->
        EctoAdapter.get(:invalid_id, assigns, live_resource)
      end
    end

    test "handles binary_id schemas: valid uuid creates equality where, invalid raises" do
      defmodule LiveResourceUUID do
        def adapter_config(:repo), do: Backpex.Adapters.EctoTest.CaptureRepo
        def adapter_config(:schema), do: Backpex.Adapters.EctoTest.TestUUID
        def adapter_config(:item_query), do: &Backpex.Adapters.Ecto.default_item_query/3
        def config(:primary_key), do: :id
        def validated_fields, do: []
      end

      assigns = %{live_action: :show}

      valid = "550e8400-e29b-41d4-a716-446655440000"
      assert {:ok, nil} = EctoAdapter.get(valid, assigns, LiveResourceUUID)
      assert_received {:repo_one, %Ecto.Query{} = query}
      assert [%{expr: where_expr}] = query.wheres
      assert match?({:==, _, _}, where_expr)

      assert_raise Ecto.NoResultsError, fn ->
        EctoAdapter.get("not-a-uuid", assigns, LiveResourceUUID)
      end
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
end
