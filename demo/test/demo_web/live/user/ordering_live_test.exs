defmodule DemoWeb.Live.User.OrderingLiveTest do
  use DemoWeb.ConnCase, async: false

  import Demo.EctoFactory
  import Phoenix.LiveViewTest

  # Users have init_order: fn -> %{by: :username, direction: :asc} end
  # The :posts and :addresses fields have orderable: false
  # The :username field is index_editable, so it renders as an input (not plain text).
  # We use the Full Name column (computed from first_name + last_name) to verify ordering.

  describe "default ordering" do
    test "orders by username ascending by default", %{conn: conn} do
      insert(:user, username: "alice", first_name: "Alice", last_name: "A")
      insert(:user, username: "bob", first_name: "Bob", last_name: "B")
      insert(:user, username: "charlie", first_name: "Charlie", last_name: "C")

      conn
      |> visit(~p"/admin/users")
      |> assert_has("table tbody tr", count: 3)
      |> assert_has("table tbody tr:first-child td", text: "Alice A")
      |> assert_has("table tbody tr:last-child td", text: "Charlie C")
    end
  end

  describe "ordering via URL params" do
    test "orders by username descending", %{conn: conn} do
      insert(:user, username: "alice", first_name: "Alice", last_name: "A")
      insert(:user, username: "bob", first_name: "Bob", last_name: "B")
      insert(:user, username: "charlie", first_name: "Charlie", last_name: "C")

      params = %{"order_by" => "username", "order_direction" => "desc"}

      conn
      |> visit(~p"/admin/users?#{params}")
      |> assert_has("table tbody tr", count: 3)
      |> assert_has("table tbody tr:first-child td", text: "Charlie C")
      |> assert_has("table tbody tr:last-child td", text: "Alice A")
    end

    test "orders by age ascending", %{conn: conn} do
      insert(:user, username: "young", first_name: "Young", last_name: "Y", age: 20)
      insert(:user, username: "old", first_name: "Old", last_name: "O", age: 80)
      insert(:user, username: "mid", first_name: "Mid", last_name: "M", age: 50)

      params = %{"order_by" => "age", "order_direction" => "asc"}

      conn
      |> visit(~p"/admin/users?#{params}")
      |> assert_has("table tbody tr", count: 3)
      |> assert_has("table tbody tr:first-child td", text: "Young Y")
      |> assert_has("table tbody tr:last-child td", text: "Old O")
    end
  end

  describe "invalid ordering params" do
    test "falls back to default order_by for invalid order_by field", %{conn: conn} do
      insert(:user, username: "alice", first_name: "Alice", last_name: "A")
      insert(:user, username: "bob", first_name: "Bob", last_name: "B")
      insert(:user, username: "charlie", first_name: "Charlie", last_name: "C")

      # order_by falls back to init_order.by (:username), direction stays as provided (:desc)
      params = %{"order_by" => "nonexistent_field", "order_direction" => "desc"}

      conn
      |> visit(~p"/admin/users?#{params}")
      |> assert_has("table tbody tr", count: 3)
      |> assert_has("table tbody tr:first-child td", text: "Charlie C")
      |> assert_has("table tbody tr:last-child td", text: "Alice A")
    end

    test "falls back to default direction for invalid order_direction", %{conn: conn} do
      insert(:user, username: "alice", first_name: "Alice", last_name: "A")
      insert(:user, username: "bob", first_name: "Bob", last_name: "B")
      insert(:user, username: "charlie", first_name: "Charlie", last_name: "C")

      params = %{"order_by" => "username", "order_direction" => "INVALID"}

      conn
      |> visit(~p"/admin/users?#{params}")
      |> assert_has("table tbody tr", count: 3)
      # Falls back to init_order direction: asc
      |> assert_has("table tbody tr:first-child td", text: "Alice A")
      |> assert_has("table tbody tr:last-child td", text: "Charlie C")
    end

    test "non-orderable field falls back to default order", %{conn: conn} do
      insert(:user, username: "alice", first_name: "Alice", last_name: "A")
      insert(:user, username: "bob", first_name: "Bob", last_name: "B")
      insert(:user, username: "charlie", first_name: "Charlie", last_name: "C")

      params = %{"order_by" => "posts", "order_direction" => "asc"}

      conn
      |> visit(~p"/admin/users?#{params}")
      |> assert_has("table tbody tr", count: 3)
      # posts is orderable: false, falls back to default: username asc
      |> assert_has("table tbody tr:first-child td", text: "Alice A")
      |> assert_has("table tbody tr:last-child td", text: "Charlie C")
    end
  end

  describe "ordering via column header click" do
    test "clicking Username column toggles to descending", %{conn: conn} do
      insert(:user, username: "alice", first_name: "Alice", last_name: "A")
      insert(:user, username: "bob", first_name: "Bob", last_name: "B")
      insert(:user, username: "charlie", first_name: "Charlie", last_name: "C")

      conn
      |> visit(~p"/admin/users")
      # Default is username asc
      |> assert_has("table tbody tr:first-child td", text: "Alice A")
      # Click Username column to toggle to desc
      |> unwrap(fn view ->
        view
        |> element("a", "Username")
        |> render_click()
      end)
      |> assert_has("table tbody tr:first-child td", text: "Charlie C")
      |> assert_has("table tbody tr:last-child td", text: "Alice A")
    end
  end
end
