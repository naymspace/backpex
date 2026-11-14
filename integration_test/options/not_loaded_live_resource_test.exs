defmodule Backpex.Integration.Options.NotLoadedLiveResourceTest do
  @moduledoc """
  Checks that `c:Backpex.LiveResource.scope/1`, `c:Backpex.LiveResource.load/1` and `c:Backpex.LiveResource.computed/1`
  apply to the first read of a LiveResource whose module the VM has not loaded yet, e.g. right after the app started.
  """
  use Backpex.DataCase, async: true

  import Backpex.Expr, only: [expr: 1]

  alias Backpex.Query
  alias Backpex.Resource
  alias Backpex.Test.NotLoadedPostLive

  # The author field of `Backpex.Test.NotLoadedPostLive`, written out so that reading it doesn't load the module.
  @user_field {:user, %{module: Backpex.Fields.BelongsTo, display_field: :full_name, options_sort: [full_name: :desc]}}

  setup do
    unload()
  end

  defp unload do
    :code.purge(NotLoadedPostLive)
    :code.delete(NotLoadedPostLive)
    :code.purge(NotLoadedPostLive)
    refute :code.is_loaded(NotLoadedPostLive)

    :ok
  end

  test "items_query/3 has the scope, the load and the computed values" do
    query = Resource.items_query([], %{}, NotLoadedPostLive)

    assert query.filter == expr(published == true)
    assert [user: %Query{computed: %{full_name: _expression}}] = query.load
    assert %{headline: _expression} = query.computed
  end

  test "get/4 hides an item outside of the scope" do
    draft = insert(:post, published: false)

    assert {:ok, nil} = Resource.get(draft.id, [], %{}, NotLoadedPostLive)
  end

  test "get/4 computes the values of an item and of its loaded relationship" do
    author = insert(:user, first_name: "Ann", last_name: "Zed")
    published = insert(:post, title: "News", published: true, user: author)

    assert {:ok, %{headline: "News!", user: %{full_name: "Ann Zed"}}} =
             Resource.get(published.id, [], %{}, NotLoadedPostLive)
  end

  test "index_query/2 has the scope, the load and the computed values" do
    query =
      Backpex.LiveResource.index_query(
        %{
          live_resource: NotLoadedPostLive,
          live_action: :index,
          filters: [],
          init_order: %{by: :id, direction: :asc},
          query_options: %{order_by: :id, order_direction: :asc, page: 1, per_page: 15}
        },
        []
      )

    assert query.filter == expr(published == true)
    assert [user: %Query{computed: %{full_name: _expression}}] = query.load
    assert %{headline: _expression} = query.computed
  end

  test "options_query/3 has the computed values of the relationship in load/1" do
    assert %{full_name: _expression} = Resource.options_query(@user_field, %{}, NotLoadedPostLive).computed
  end

  test "list_options/4 sorts the options by a computed value of load/1" do
    insert(:user, first_name: "Ann", last_name: "Zed")
    insert(:user, first_name: "Zoe", last_name: "Abe")

    assert {:ok, users} = Resource.list_options(@user_field, [], %{}, NotLoadedPostLive)
    assert Enum.map(users, & &1.full_name) == ["Zoe Abe", "Ann Zed"]
  end
end
