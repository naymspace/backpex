defmodule Backpex.Integration.Index.OrderingTest do
  use Backpex.ConnCase, async: true

  # Tags have `init_order: %{by: :name, direction: :desc}`.
  describe "init_order as a map" do
    setup do
      for name <- ["Alpha", "Beta", "Gamma"], do: insert(:tag, name: name)
      :ok
    end

    test "orders by the init_order by default", %{conn: conn} do
      conn
      |> visit(~p"/admin/tags")
      |> assert_order(["Gamma", "Beta", "Alpha"])
    end

    test "orders ascending by the order params", %{conn: conn} do
      conn
      |> visit(~p"/admin/tags?#{%{"order_by" => "name", "order_direction" => "asc"}}")
      |> assert_order(["Alpha", "Beta", "Gamma"])
    end

    test "orders descending by the order params", %{conn: conn} do
      conn
      |> visit(~p"/admin/tags?#{%{"order_by" => "name", "order_direction" => "desc"}}")
      |> assert_order(["Gamma", "Beta", "Alpha"])
    end

    test "falls back to the init_order column for an unknown order_by and keeps the direction", %{conn: conn} do
      conn
      |> visit(~p"/admin/tags?#{%{"order_by" => "nonexistent_field", "order_direction" => "asc"}}")
      |> assert_order(["Alpha", "Beta", "Gamma"])
    end

    test "falls back to the init_order when both order params are invalid", %{conn: conn} do
      conn
      |> visit(~p"/admin/tags?#{%{"order_by" => "nonexistent_field", "order_direction" => "invalid"}}")
      |> assert_order(["Gamma", "Beta", "Alpha"])
    end

    test "falls back to the init_order direction for an invalid order_direction", %{conn: conn} do
      conn
      |> visit(~p"/admin/tags?#{%{"order_by" => "name", "order_direction" => "invalid"}}")
      |> assert_order(["Gamma", "Beta", "Alpha"])
    end

    test "clicking the column header toggles the direction", %{conn: conn} do
      conn
      |> visit(~p"/admin/tags")
      |> assert_order(["Gamma", "Beta", "Alpha"])
      |> click_link("thead a", "Name")
      |> assert_order(["Alpha", "Beta", "Gamma"])
    end

    test "clicking the column header twice returns to the original direction", %{conn: conn} do
      conn
      |> visit(~p"/admin/tags")
      |> click_link("thead a", "Name")
      |> assert_order(["Alpha", "Beta", "Gamma"])
      |> click_link("thead a", "Name")
      |> assert_order(["Gamma", "Beta", "Alpha"])
    end
  end

  # Users have `init_order: &init_order/1` (username ascending). The username column is index editable, so rows are
  # identified by the "Full Name" column.
  describe "init_order as a function" do
    setup do
      insert(:user, username: "alice", first_name: "Alice", last_name: "A", age: 50)
      insert(:user, username: "bob", first_name: "Bob", last_name: "B", age: 80)
      insert(:user, username: "charlie", first_name: "Charlie", last_name: "C", age: 20)
      :ok
    end

    test "orders by the init_order by default", %{conn: conn} do
      conn
      |> visit(~p"/admin/users")
      |> assert_order(["Alice A", "Bob B", "Charlie C"])
    end

    test "orders by a number column", %{conn: conn} do
      conn
      |> visit(~p"/admin/users?#{%{"order_by" => "age", "order_direction" => "asc"}}")
      |> assert_order(["Charlie C", "Alice A", "Bob B"])
    end

    test "falls back to the init_order for a field that is not orderable", %{conn: conn} do
      conn
      |> visit(~p"/admin/users?#{%{"order_by" => "posts", "order_direction" => "asc"}}")
      |> assert_order(["Alice A", "Bob B", "Charlie C"])
    end
  end

  describe "default init_order" do
    test "orders by the primary key ascending", %{conn: conn} do
      addresses = for street <- ["First Street", "Second Street", "Third Street"], do: insert(:address, street: street)

      # Addresses have random UUID primary keys, so the expected order is derived from the inserted records.
      expected = addresses |> Enum.sort_by(& &1.id) |> Enum.map(& &1.street)

      conn
      |> visit(~p"/admin/addresses")
      |> assert_order(expected)
    end

    test "orders by a currency column", %{conn: conn} do
      insert(:product, name: "Expensive", price: Money.new(50_000, :USD))
      insert(:product, name: "Cheap", price: Money.new(10_00, :USD))
      insert(:product, name: "Mid", price: Money.new(10_000, :USD))

      conn
      |> visit(~p"/admin/products?#{%{"order_by" => "price", "order_direction" => "asc"}}")
      |> assert_order(["Cheap", "Mid", "Expensive"])
    end
  end

  # Short links have `primary_key: :short_key` and no `id` column.
  describe "string primary key without an id column" do
    setup do
      for short_key <- ["ccc", "aaa", "bbb"], do: insert(:short_link, short_key: short_key)
      :ok
    end

    test "orders by the primary key ascending by default", %{conn: conn} do
      conn
      |> visit(~p"/admin/short-links")
      |> assert_order(["aaa", "bbb", "ccc"])
    end

    test "falls back to the primary key for an unknown order_by", %{conn: conn} do
      conn
      |> visit(~p"/admin/short-links?#{%{"order_by" => "nonexistent_field", "order_direction" => "asc"}}")
      |> assert_order(["aaa", "bbb", "ccc"])
    end

    test "clicking the primary key column header toggles the direction", %{conn: conn} do
      conn
      |> visit(~p"/admin/short-links")
      |> assert_order(["aaa", "bbb", "ccc"])
      |> click_link("thead a", "URL Suffix")
      |> assert_order(["ccc", "bbb", "aaa"])
    end
  end

  defp assert_order(session, texts) do
    session = assert_has(session, "table tbody tr", count: length(texts))

    texts
    |> Enum.with_index(1)
    |> Enum.reduce(session, fn {text, index}, session ->
      assert_has(session, "table tbody tr:nth-child(#{index}) td", text: text)
    end)
  end
end
