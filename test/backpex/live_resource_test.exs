defmodule Backpex.LiveResourceTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  alias Backpex.Adapters.Ecto, as: EctoAdapter
  alias Backpex.Expr
  alias Backpex.ItemActions.Delete
  alias Backpex.LiveResource
  alias Backpex.LiveResource.Index
  alias Phoenix.LiveView.Socket

  defmodule TestAuthor do
    use Ecto.Schema

    schema "authors" do
      field :name, :string
    end
  end

  defmodule TestPost do
    use Ecto.Schema

    @primary_key {:id, :binary_id, autogenerate: true}
    schema "posts" do
      field :title, :string
      belongs_to :author, TestAuthor
    end
  end

  defmodule TestPostLive do
    @moduledoc false
    def adapter_config(:schema), do: Backpex.LiveResourceTest.TestPost
    def adapter_config(:item_query), do: &EctoAdapter.default_item_query/3
    def config(:adapter), do: EctoAdapter
    def config(:full_text_search), do: nil
    def config(:primary_key), do: :id
    def config(:order_nulls), do: :default
  end

  defmodule NullsFirstPostLive do
    @moduledoc false
    def adapter_config(:schema), do: Backpex.LiveResourceTest.TestPost
    def adapter_config(:item_query), do: &EctoAdapter.default_item_query/3
    def config(:adapter), do: EctoAdapter
    def config(:full_text_search), do: nil
    def config(:primary_key), do: :id
    def config(:order_nulls), do: :first
  end

  defmodule IndexFieldsPostLive do
    @moduledoc false
    def adapter_config(:schema), do: Backpex.LiveResourceTest.TestPost
    def config(:adapter), do: EctoAdapter
    def config(:full_text_search), do: nil
    def config(:primary_key), do: :id
    def config(:order_nulls), do: :default
    def fields(:index, _assigns), do: [title: %{module: Backpex.Fields.Text, label: "Title", searchable: true}]
  end

  defmodule SelectFieldLive do
    @moduledoc false
    def config(:adapter), do: Backpex.Adapters.Ecto
    def fields, do: [title: %{module: Backpex.Fields.Text, label: "Title", select: dynamic([p], p.title)}]
  end

  defmodule StubSelectFieldLive do
    @moduledoc false
    def config(:adapter), do: Backpex.Test.StubAdapter
    def fields, do: [title: %{module: Backpex.Fields.Text, label: "Title", select: dynamic([p], p.title)}]
  end

  defmodule AllContextLive do
    @moduledoc false
    def config(:context_assigns), do: :all
  end

  describe "fields/3" do
    test "accepts the field options of the adapter" do
      assert [title: %{select: %Ecto.Query.DynamicExpr{}}] = LiveResource.fields(SelectFieldLive, :index, %{})
    end

    test "rejects field options the adapter doesn't add" do
      assert_raise RuntimeError, ~r/unknown options \[:select\]/, fn ->
        LiveResource.fields(StubSelectFieldLive, :index, %{})
      end
    end
  end

  defmodule ListContextLive do
    @moduledoc false
    def config(:context_assigns), do: [:current_user]
  end

  describe "context/1" do
    test "passes all assigns except the change tracking ones by default" do
      assigns = %{
        __changed__: %{},
        backpex_view_context: %{},
        live_resource: AllContextLive,
        items: [],
        current_user: :user
      }

      assert LiveResource.context(assigns) == %{
               __changed__: nil,
               live_resource: AllContextLive,
               items: [],
               current_user: :user
             }
    end

    test "passes the configured assigns, the ones Backpex needs and a socket for building routes" do
      socket = %Socket{endpoint: :endpoint, router: :router, assigns: %{items: []}}

      assigns = %{
        __changed__: %{},
        live_resource: ListContextLive,
        live_action: :index,
        params: %{},
        fields: [],
        item_actions: [],
        return_to: "/posts",
        item: %{id: 1},
        items: [],
        current_user: :user,
        socket: socket
      }

      assert LiveResource.context(assigns) == %{
               __changed__: nil,
               live_resource: ListContextLive,
               live_action: :index,
               params: %{},
               fields: [],
               item_actions: [],
               return_to: "/posts",
               item: %{id: 1},
               current_user: :user,
               socket: %Socket{endpoint: :endpoint, router: :router}
             }
    end

    test "can be assigned to by callbacks" do
      for live_resource <- [AllContextLive, ListContextLive] do
        context = LiveResource.context(%{__changed__: %{}, live_resource: live_resource, current_user: :user})

        assert %{published: true} = Phoenix.Component.assign(context, :published, true)
      end
    end
  end

  describe "default_attrs/3" do
    test "puts the default of a field for a single associated item under the key the association is based on" do
      fields = [
        author: %{module: Backpex.Fields.BelongsTo, display_field: :name, default: fn _assigns -> 1 end},
        title: %{module: Backpex.Fields.Text, default: fn assigns -> assigns.title end}
      ]

      assert LiveResource.default_attrs(:new, fields, %{live_resource: TestPostLive, title: "Title"}) ==
               %{author_id: 1, title: "Title"}
    end
  end

  describe "index_query/2" do
    defp index_query(live_resource, fields, order_by, init_order \\ %{by: :id, direction: :asc}) do
      LiveResource.index_query(
        %{
          live_resource: live_resource,
          live_action: :index,
          filters: [],
          fields: fields,
          init_order: init_order,
          query_options: %{order_by: order_by, order_direction: :desc, page: 1, per_page: 15}
        },
        fields
      )
    end

    defp order_bys(query), do: query |> EctoAdapter.ecto_query() |> Map.fetch!(:order_bys) |> Enum.flat_map(& &1.expr)

    test "index_query/1 has the index fields of the LiveResource, not the fields of a resource action" do
      query =
        LiveResource.index_query(%{
          live_resource: IndexFieldsPostLive,
          live_action: :resource_action,
          filters: [],
          fields: [file_name: %{module: Backpex.Fields.Text, label: "File name"}],
          init_order: %{by: :id, direction: :asc},
          query_options: %{order_by: :title, order_direction: :asc, page: 1, per_page: 15, search: "x"}
        })

      assert query.sort == [{Expr.ref(:title), :asc}]
      assert query.search.targets == [Expr.ref(:title)]
    end

    test "sorts by the init order when ordering by a column that is not a declared field" do
      # :id is the default init_order column, but a primary key is virtually never declared as a field. The order must
      # still reach the query.
      query = index_query(TestPostLive, [{:title, %{module: Backpex.Fields.Text}}], :id)

      assert query.sort == []
      assert query.default_sort == [{Expr.ref(:id), :asc}]
      assert [{:asc, order_expression}] = order_bys(query)
      assert Macro.to_string(order_expression) =~ "id"
    end

    test "orders by the primary key without NULLS FIRST/LAST" do
      fields = [{:id, %{module: Backpex.Fields.Text, order_nulls: :last}}, {:title, %{module: Backpex.Fields.Text}}]

      query = index_query(NullsFirstPostLive, fields, :id)
      assert query.sort == [{Expr.ref(:id), :desc_nulls_last}]
      assert [{:desc, _id}] = order_bys(query)

      query = index_query(NullsFirstPostLive, fields, :unknown)
      assert query.default_sort == [{Expr.ref(:id), :asc_nulls_first}]
      assert [{:asc, _id}] = order_bys(query)
    end

    test "uses the order_nulls option of the live resource" do
      fields = [{:title, %{module: Backpex.Fields.Text}}]

      assert index_query(TestPostLive, fields, :title).sort == [{Expr.ref(:title), :desc}]
      assert index_query(NullsFirstPostLive, fields, :title).sort == [{Expr.ref(:title), :desc_nulls_first}]

      init_order = %{by: :title, direction: :asc}

      assert index_query(NullsFirstPostLive, [], :title, init_order).default_sort == [
               {Expr.ref(:title), :asc_nulls_first}
             ]
    end

    test "prefers the order_nulls option of the field" do
      fields = [{:title, %{module: Backpex.Fields.Text, order_nulls: :last}}]

      assert index_query(NullsFirstPostLive, fields, :title).sort == [{Expr.ref(:title), :desc_nulls_last}]
    end

    test "applies order_nulls to a field with a select expression named like the primary key" do
      select = dynamic([testpost: p], fragment("upper(?)", p.title))
      fields = [{:id, %{module: Backpex.Fields.Text, select: select}}]

      query = index_query(NullsFirstPostLive, fields, :id)
      assert query.sort == [{Expr.ref(:id), :desc_nulls_first}]
      assert [{:desc_nulls_first, _select}] = order_bys(query)
    end

    test "applies order_nulls to the primary key of an association" do
      fields = [{:author, %{module: Backpex.Fields.BelongsTo, display_field: :id}}]

      query = index_query(NullsFirstPostLive, fields, :author)
      assert query.sort == [{Expr.ref([:author], :id), :desc_nulls_first}]
      assert [{:desc_nulls_first, _author_id}] = order_bys(query)
    end
  end

  describe "return_to_param/1" do
    test "returns a same-origin absolute path" do
      assert LiveResource.return_to_param(%{"return_to" => "/admin/posts"}) == "/admin/posts"
    end

    test "keeps a query string on the path" do
      assert LiveResource.return_to_param(%{"return_to" => "/admin/posts?page=2"}) == "/admin/posts?page=2"
    end

    test "rejects a value with a scheme" do
      assert LiveResource.return_to_param(%{"return_to" => "https://evil.com"}) == nil
    end

    test "rejects a protocol-relative value" do
      assert LiveResource.return_to_param(%{"return_to" => "//evil.com"}) == nil
    end

    test "rejects a backslash-prefixed value" do
      # A literal backslash (single-level escaping here); browsers may normalize it to "//".
      assert LiveResource.return_to_param(%{"return_to" => "/\\evil.com"}) == nil
    end

    test "rejects a value containing control characters" do
      assert LiveResource.return_to_param(%{"return_to" => "/foo\evil.com"}) == nil
      assert LiveResource.return_to_param(%{"return_to" => "/foo\nbar"}) == nil
    end

    test "returns nil when the param is missing" do
      assert LiveResource.return_to_param(%{}) == nil
    end

    test "returns nil when the param is not a string" do
      assert LiveResource.return_to_param(%{"return_to" => ["/admin"]}) == nil
    end
  end

  describe "fetch_action!/2" do
    @actions [delete: %{module: Delete}, show: %{module: Backpex.ItemActions.Show}]

    test "returns the registration for a known key" do
      assert LiveResource.fetch_action!(@actions, "delete") == {:delete, %{module: Delete}}
    end

    test "raises NoResultsError for an unregistered key" do
      # Matching binaries rather than `String.to_existing_atom/1` keeps a forged key a 404 instead
      # of an ArgumentError that depends on which atoms happen to exist in the running system.
      assert_raise Backpex.NoResultsError, fn ->
        LiveResource.fetch_action!(@actions, "no_such_action_key")
      end
    end

    test "raises NoResultsError for an existing atom that is not registered here" do
      assert_raise Backpex.NoResultsError, fn ->
        LiveResource.fetch_action!(@actions, "edit")
      end
    end

    test "raises NoResultsError for a non-binary key" do
      assert_raise Backpex.NoResultsError, fn ->
        LiveResource.fetch_action!(@actions, ["delete"])
      end
    end
  end

  describe "search_options/2" do
    @searchable_fields [{:title, %{module: Backpex.Fields.Text, searchable: true}}]

    test "keeps a string search term" do
      assert {"hello", [{:title, %{searchable: true}}]} =
               LiveResource.search_options(%{"search" => "hello"}, @searchable_fields)

      assert {"hello", _fields} = LiveResource.search_options(%{search: "hello"}, @searchable_fields)
      assert {"", _fields} = LiveResource.search_options(%{}, @searchable_fields)
    end
  end

  describe "Index.handle_event/3" do
    test "change-filter is a no-op for filters that are not a map" do
      # `filters` arrives in a client-controlled event payload; a tampered value
      # must not crash the LiveView.
      socket = %Socket{assigns: %{__changed__: %{}, query_options: %{filters: %{}}}}

      for filters <- ["active", ["active"], 1] do
        assert {:noreply, ^socket} =
                 Index.handle_event("change-filter", %{"filters" => filters}, socket)
      end
    end

    test "filter-preset-selected is a no-op for a field or preset the resource does not know" do
      # `field` and `preset-index` arrive in a client-controlled event payload;
      # a tampered value must not crash the LiveView.
      presets = [%{label: "Active", values: fn -> ["active"] end}]

      socket = %Socket{
        assigns: %{
          __changed__: %{},
          query_options: %{filters: %{}},
          filters: [status: %{module: nil, presets: presets}, published: %{module: nil}]
        }
      }

      for params <- [
            %{"field" => "status", "preset-index" => "abc"},
            %{"field" => "status", "preset-index" => "1abc"},
            %{"field" => "status", "preset-index" => "1"},
            %{"field" => "status", "preset-index" => "-1"},
            %{"field" => "status", "preset-index" => 0},
            %{"field" => "not_an_existing_atom_8f3a1c", "preset-index" => "0"},
            %{"field" => "title", "preset-index" => "0"},
            %{"field" => "published", "preset-index" => "0"},
            %{"field" => "status"},
            %{}
          ] do
        assert {:noreply, ^socket} =
                 Index.handle_event("filter-preset-selected", params, socket)
      end
    end

    test "toggle_column is a no-op for a field the resource does not know" do
      # `field` arrives in a client-controlled event payload; an unknown name
      # must not crash the LiveView.
      socket = %Socket{
        assigns: %{__changed__: %{}, active_fields: [{:title, %{active: true}}]}
      }

      assert {:noreply, ^socket} =
               Index.handle_event("toggle_column", %{"field" => "bogus"}, socket)
    end

    test "select-page-size and index-search are no-ops for a payload without a value" do
      # The payload is client-controlled. A tampered value is validated in `handle_params/3`; a payload
      # without one must not crash the LiveView.
      socket = %Socket{assigns: %{__changed__: %{}, query_options: %{}, params: %{}}}

      for {event, params} <- [
            {"select-page-size", %{}},
            {"select-page-size", %{"select_per_page" => "15"}},
            {"index-search", %{}},
            {"index-search", %{"index_search" => "R&D"}}
          ] do
        assert {:noreply, ^socket} = Index.handle_event(event, params, socket)
      end
    end
  end
end
