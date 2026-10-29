defmodule Backpex.Integration.Options.ComputedTest do
  @moduledoc """
  Checks aggregates over relationships to many items as computed values, through `Backpex.Test.UserStatsLive`.
  """
  use Backpex.ConnCase, async: true

  setup do
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
      |> Backpex.Resource.items_query(%{}, Backpex.Test.UserStatsLive)
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

  test "reads the aggregates of a single item", %{conn: conn, ann: ann} do
    conn
    |> visit(~p"/admin/user-stats/#{ann.id}/show")
    |> assert_has("dd", text: "Big")
    |> assert_has("dd", text: "elixir")
  end
end
