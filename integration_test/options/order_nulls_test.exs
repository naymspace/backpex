defmodule Backpex.Integration.Options.OrderNullsTest do
  @moduledoc """
  Checks where PostgreSQL places `NULL` values with the `order_nulls` option of the LiveResource and the field. The
  LiveResources of `Backpex.Test.OrderNullsUserLive` differ only in their `order_nulls` option; `Backpex.LiveResourceTest`
  checks the order criteria with fake LiveResources.
  """
  use Backpex.ConnCase, async: true

  setup do
    insert(:user, username: "alice", age: 50, avatar: "b.png")
    insert(:user, username: "bob", age: nil, avatar: nil)
    insert(:user, username: "charlie", age: 20, avatar: "a.png")
    :ok
  end

  # Bob has no age. PostgreSQL treats NULL as larger than any value.
  @expected_orders [
    {"default", "asc", ["charlie", "alice", "bob"]},
    {"default", "desc", ["bob", "alice", "charlie"]},
    {"first", "asc", ["bob", "charlie", "alice"]},
    {"first", "desc", ["bob", "alice", "charlie"]},
    {"last", "asc", ["charlie", "alice", "bob"]},
    {"last", "desc", ["alice", "charlie", "bob"]},
    {"smallest", "asc", ["bob", "charlie", "alice"]},
    {"smallest", "desc", ["alice", "charlie", "bob"]}
  ]

  for {order_nulls, direction, usernames} <- @expected_orders do
    test "order_nulls #{order_nulls} places the NULL age when ordering #{direction}", %{conn: conn} do
      conn
      |> visit("/admin/order-nulls-#{unquote(order_nulls)}-users?order_by=age&order_direction=#{unquote(direction)}")
      |> assert_order(unquote(usernames))
    end
  end

  # The avatar field has `order_nulls: :last`, which overrides the `order_nulls: :first` of the LiveResource.
  for {direction, usernames} <- [{"asc", ["charlie", "alice", "bob"]}, {"desc", ["alice", "charlie", "bob"]}] do
    test "the order_nulls option of a field overrides the one of the LiveResource (#{direction})", %{conn: conn} do
      conn
      |> visit(~p"/admin/order-nulls-first-users?#{%{"order_by" => "avatar", "order_direction" => unquote(direction)}}")
      |> assert_order(unquote(usernames))
    end
  end

  defp assert_order(session, usernames) do
    session = assert_has(session, "table tbody tr", count: length(usernames))

    usernames
    |> Enum.with_index(1)
    |> Enum.reduce(session, fn {username, index}, session ->
      assert_has(session, "table tbody tr:nth-child(#{index}) td", text: username, exact: true)
    end)
  end
end
