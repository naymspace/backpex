defmodule Backpex.Integration.Options.ComputedTest do
  @moduledoc """
  Checks aggregates over relationships to many items as computed values, through `Backpex.Test.UserStatsLive`.
  """
  use Backpex.ConnCase, async: true

  import Backpex.Expr, only: [expr: 1]
  import Ecto.Query, only: [dynamic: 2]

  alias Backpex.Expr
  alias Backpex.Query
  alias Backpex.Resource
  alias Backpex.Test.UserStatsLive

  setup do
    # Some tests build the query of the LiveResource before any view has loaded its module.
    Code.ensure_loaded!(UserStatsLive)

    ann = insert(:user, username: "ann", posts: [])
    bob = insert(:user, username: "bob", posts: [])

    insert(:post, user: ann, title: "Small", likes: 1, published: false, tags: [build(:tag, name: "zig")])
    insert(:post, user: ann, title: "Big", likes: 9, published: true, tags: [build(:tag, name: "elixir")])

    %{ann: ann, bob: bob}
  end

  test "shows the aggregates of the related items, and nil or 0 without related items", %{conn: conn} do
    conn
    |> visit(~p"/admin/user-stats")
    |> assert_rows("table tbody", ["ann", "bob"])
    |> assert_has("tbody tr:nth-child(1) td", text: "Big", exact: true)
    |> assert_has("tbody tr:nth-child(1) td", text: "elixir", exact: true)
    |> assert_has("tbody tr:nth-child(1) td", text: "10", exact: true)
    |> assert_has("tbody tr:nth-child(1) td", text: "2", exact: true)
    |> assert_has("tbody tr:nth-child(1) td", text: "1", exact: true)
    |> assert_has("tbody tr:nth-child(2) td", text: "0", exact: true)
  end

  test "reads aggregates that share a join and computes with aggregates", %{ann: ann, bob: bob} do
    {:ok, users} =
      []
      |> Backpex.Resource.items_query(%{}, UserStatsLive)
      |> Backpex.Query.sort(username: :asc)
      |> Backpex.Resource.read()

    assert [
             %{id: ann_id, top_post: "Big", top_post_likes: 9, draft_count: 1},
             %{id: bob_id, top_post: nil, top_post_likes: nil, draft_count: 0}
           ] = users

    assert {ann_id, bob_id} == {ann.id, bob.id}
  end

  test "sorts by an aggregate and searches it", %{conn: conn} do
    conn
    |> visit(~p"/admin/user-stats?#{%{order_by: "post_count", order_direction: "asc"}}")
    |> assert_rows("table tbody", ["bob", "ann"])

    conn
    |> visit(~p"/admin/user-stats?#{%{search: "bi"}}")
    |> assert_rows("table tbody", ["ann"])
  end

  test "filters and aggregates by aggregates that share the join of a computed value", %{ann: ann} do
    query = Resource.items_query([], %{}, UserStatsLive)
    # Only differ in their value from `total_likes` and from `top_post`.
    doubled_likes = Expr.aggregate(:sum, :posts, value: expr(likes * 2))
    top_post_published = Expr.aggregate(:first, :posts, value: expr(published), sort: [likes: :desc])

    for condition <- [expr(^doubled_likes > 10), expr(^top_post_published == true)] do
      filtered = Query.filter(query, condition)

      assert {:ok, [%{id: id, total_likes: 10, top_post: "Big"}]} = Resource.read(filtered)
      assert id == ann.id
      assert Resource.count(filtered) == {:ok, 1}
    end

    assert {:ok, %{doubled_likes: sum, popular: 1}} =
             query
             |> Query.aggregate(:doubled_likes, {:sum, doubled_likes})
             |> Query.aggregate(:popular, :count, where: expr(^doubled_likes > 10))
             |> Resource.aggregate()

    assert Decimal.equal?(sum, 20)
  end

  test "the index view filters by an aggregate and shows a metric of an aggregate", %{conn: conn} do
    conn
    |> visit(~p"/admin/user-stats")
    |> assert_rows("table tbody", ["ann", "bob"])
    |> assert_has(".card-body", text: "Doubled likes 20", exact: true)

    conn
    |> visit(~p"/admin/user-stats?#{%{filters: %{top_post: ["published"]}}}")
    |> assert_rows("table tbody", ["ann"])
    |> assert_has(".card-body", text: "Doubled likes 20", exact: true)
  end

  test "paginates and counts the items sorted by an aggregate and searched by one", %{conn: conn} do
    # With ann and bob 18 users, more than the 15 of a page. bob has no likes, which sorts last.
    names =
      for number <- 1..16 do
        name = "user#{String.pad_leading("#{number}", 2, "0")}"
        user = insert(:user, username: name, posts: [])
        insert(:post, user: user, title: "Post of #{name}", likes: number * 100)

        name
      end

    {first_page, second_page} = Enum.split(["ann" | names] ++ ["bob"], 15)
    sorted = %{order_by: "total_likes", order_direction: "asc"}

    conn
    |> visit(~p"/admin/user-stats?#{sorted}")
    |> assert_rows("table tbody", first_page)
    |> assert_has("div", text: "Items 1 to 15 (18 total)", exact: true)

    conn
    |> visit(~p"/admin/user-stats?#{Map.put(sorted, :page, 2)}")
    |> assert_rows("table tbody", second_page)
    |> assert_has("div", text: "Items 16 to 18 (18 total)", exact: true)

    # The search matches the top posts of the 16 users.
    conn
    |> visit(~p"/admin/user-stats?#{Map.merge(sorted, %{search: "post of", page: 2})}")
    |> assert_rows("table tbody", ["user16"])
    |> assert_has("div", text: "Items 16 to 16 (16 total)", exact: true)

    query =
      []
      |> Resource.items_query(%{}, UserStatsLive)
      |> Query.sort(total_likes: :desc_nulls_last)
      |> Query.offset(15)
      |> Query.limit(15)

    assert {:ok, [%{username: "user01"}, %{username: "ann"}, %{username: "bob"}]} = Resource.read(query)
    assert Resource.count(query) == {:ok, 18}
  end

  test "computes a correlated subquery of the related items as a native value" do
    post_count =
      Expr.native(
        Backpex.Adapters.Ecto,
        dynamic([user: u], fragment("(SELECT count(*) FROM posts WHERE posts.user_id = ?)", u.id))
      )

    query = UserStatsLive |> Query.new() |> Query.compute(:post_count, post_count) |> Query.sort(post_count: :desc)

    assert {:ok, [%{username: "ann", post_count: 2}, %{username: "bob", post_count: 0}]} = Resource.read(query)
  end

  test "reads the aggregates of a single item", %{conn: conn, ann: ann} do
    conn
    |> visit(~p"/admin/user-stats/#{ann.id}/show")
    |> assert_has("dd", text: "Big")
    |> assert_has("dd", text: "elixir")
  end
end
