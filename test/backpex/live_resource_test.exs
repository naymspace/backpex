defmodule Backpex.LiveResourceTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  alias Backpex.Adapters.Ecto, as: EctoAdapter
  alias Backpex.ItemActions.Delete
  alias Backpex.LiveResource
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
    def config(:adapter), do: Backpex.Adapters.Ecto
    def config(:primary_key), do: :id
    def config(:order_nulls), do: :default
  end

  defmodule NullsFirstPostLive do
    @moduledoc false
    def adapter_config(:schema), do: Backpex.LiveResourceTest.TestPost
    def config(:primary_key), do: :id
    def config(:order_nulls), do: :first
  end

  defmodule AllContextLive do
    @moduledoc false
    def config(:context_assigns), do: :all
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

  describe "build_criteria/1" do
    defp order_criteria(live_resource, fields, order_by, init_order \\ %{by: :id, direction: :asc}) do
      assigns = %{
        live_resource: live_resource,
        filters: [],
        fields: fields,
        init_order: init_order,
        query_options: %{order_by: order_by, order_direction: :desc, page: 1, per_page: 15}
      }

      assigns
      |> LiveResource.build_criteria()
      |> Keyword.fetch!(:order)
    end

    test "builds an order criteria the adapter applies when ordering by a column that is not a declared field" do
      # :id is the default init_order column, but a primary key is virtually never
      # declared as a field. The order criteria must still reach the query.
      fields = [{:title, %{module: Backpex.Fields.Text}}]

      assigns = %{
        live_resource: TestPostLive,
        filters: [],
        fields: fields,
        init_order: %{by: :id, direction: :asc},
        query_options: %{order_by: :id, order_direction: :asc, page: 1, per_page: 15}
      }

      criteria = LiveResource.build_criteria(assigns)

      query =
        TestPost
        |> from(as: ^EctoAdapter.name_by_schema(TestPost))
        |> EctoAdapter.apply_criteria(criteria, fields, TestPost)

      assert %{order_bys: [%{expr: [{:asc, order_expression}]}]} = query
      assert Macro.to_string(order_expression) =~ "id"
    end

    test "orders by the primary key without NULLS FIRST/LAST" do
      fields = [{:id, %{module: Backpex.Fields.Text, order_nulls: :last}}, {:title, %{module: Backpex.Fields.Text}}]

      assert %{by: :id, nulls: :default} = order_criteria(NullsFirstPostLive, fields, :id)
      assert %{by: :id, field_name: nil, nulls: :default} = order_criteria(NullsFirstPostLive, fields, :unknown)
    end

    test "uses the order_nulls option of the live resource" do
      fields = [{:title, %{module: Backpex.Fields.Text}}]

      assert %{by: :title, nulls: :default} = order_criteria(TestPostLive, fields, :title)
      assert %{by: :title, nulls: :first} = order_criteria(NullsFirstPostLive, fields, :title)

      init_order = %{by: :title, direction: :asc}
      assert %{by: :title, field_name: nil, nulls: :first} = order_criteria(NullsFirstPostLive, [], :title, init_order)
    end

    test "prefers the order_nulls option of the field" do
      fields = [{:title, %{module: Backpex.Fields.Text, order_nulls: :last}}]

      assert %{by: :title, nulls: :last} = order_criteria(NullsFirstPostLive, fields, :title)
    end

    test "applies order_nulls to a field with a select expression named like the primary key" do
      select = dynamic([testpost: p], fragment("upper(?)", p.title))
      fields = [{:id, %{module: Backpex.Fields.Text, select: select}}]

      assert %{by: :id, nulls: :first} = order_criteria(NullsFirstPostLive, fields, :id)
    end

    test "applies order_nulls to the primary key of an association" do
      fields = [{:author, %{module: Backpex.Fields.BelongsTo, display_field: :id}}]

      assert %{by: :id, field_name: :author, nulls: :first} = order_criteria(NullsFirstPostLive, fields, :author)
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

  describe "Index.handle_event/3" do
    test "toggle_column is a no-op for a field the resource does not know" do
      # `field` arrives in a client-controlled event payload; an unknown name
      # must not crash the LiveView.
      socket = %Socket{
        assigns: %{__changed__: %{}, active_fields: [{:title, %{active: true}}]}
      }

      assert {:noreply, ^socket} =
               Backpex.LiveResource.Index.handle_event("toggle_column", %{"field" => "bogus"}, socket)
    end
  end
end
