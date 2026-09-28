defmodule Backpex.LiveResourceTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  alias Backpex.Adapters.Ecto, as: EctoAdapter
  alias Backpex.ItemActions.Delete
  alias Backpex.LiveResource

  defmodule TestPost do
    use Ecto.Schema

    @primary_key {:id, :binary_id, autogenerate: true}
    schema "posts" do
      field :title, :string
    end
  end

  defmodule TestPostLive do
    @moduledoc false
    def adapter_config(:schema), do: Backpex.LiveResourceTest.TestPost
  end

  describe "build_criteria/1" do
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
        |> EctoAdapter.apply_criteria(criteria, fields)

      assert %{order_bys: [%{expr: [{:asc_nulls_first, order_expression}]}]} = query
      assert Macro.to_string(order_expression) =~ "id"
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
      socket = %Phoenix.LiveView.Socket{
        assigns: %{__changed__: %{}, active_fields: [{:title, %{active: true}}]}
      }

      assert {:noreply, ^socket} =
               Backpex.LiveResource.Index.handle_event("toggle_column", %{"field" => "bogus"}, socket)
    end
  end
end
