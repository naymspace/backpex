defmodule DemoWeb.Live.User.IndexLiveTest do
  use DemoWeb.ConnCase, async: false

  import Demo.EctoFactory
  import Phoenix.LiveViewTest
  import Demo.Support.LiveResourceTests

  describe "users live resource index" do
    test "is rendered", %{conn: conn} do
      insert_list(3, :user)

      conn
      |> visit(~p"/admin/users")
      |> assert_has("h1", text: "Users", exact: true)
      |> assert_has("button", text: "New User", exact: true)
      |> assert_has("div", text: "Items 1 to 3 (3 total)", exact: true)
      |> assert_has("table tbody tr", count: 3)
    end

    test "renders users with username", %{conn: conn} do
      user = insert(:user, %{username: "testuser123"})

      conn
      |> visit(~p"/admin/users")
      # Username field is index_editable, so it renders as an input
      |> assert_has("input[value='#{user.username}']")
    end

    test "search finds users by username", %{conn: conn} do
      insert(:user, %{username: "alice_wonderland"})
      insert(:user, %{username: "bob_builder"})

      conn
      |> visit(~p"/admin/users")
      |> assert_has(".table tbody tr", count: 2)
      |> unwrap(fn view ->
        view
        |> form("#index-search-form", index_search: %{value: "alice"})
        |> render_change()
      end)
      |> assert_has("table tbody tr", count: 1)
      # Username field is index_editable, so it renders as an input
      |> assert_has("input[value='alice_wonderland']")
      |> refute_has("input[value='bob_builder']")
    end

    test "search finds users by first_name", %{conn: conn} do
      insert(:user, %{first_name: "John", last_name: "Doe"})
      insert(:user, %{first_name: "Jane", last_name: "Smith"})

      conn
      |> visit(~p"/admin/users")
      |> assert_has(".table tbody tr", count: 2)
      |> unwrap(fn view ->
        view
        |> form("#index-search-form", index_search: %{value: "John"})
        |> render_change()
      end)
      |> assert_has("table tbody tr", count: 1)
      |> assert_has("tr", text: "John Doe")
    end

    test "soft-deleted users are filtered out", %{conn: conn} do
      insert(:user, %{username: "active_user"})
      insert(:user, %{username: "deleted_user", deleted_at: DateTime.utc_now()})

      conn
      |> visit(~p"/admin/users")
      |> assert_has(".table tbody tr", count: 1)
      # Username field is index_editable, so it renders as an input
      |> assert_has("input[value='active_user']")
      |> refute_has("input[value='deleted_user']")
    end

    test "metrics display min_age and max_age values", %{conn: conn} do
      insert(:user, %{age: 25})
      insert(:user, %{age: 45})
      insert(:user, %{age: 65})

      conn
      |> visit(~p"/admin/users")
      |> assert_has("div", text: "Min age")
      |> assert_has("div", text: "25 years")
      |> assert_has("div", text: "Max age")
      |> assert_has("div", text: "65 years")
    end

    test "basic functionality", %{conn: conn} do
      users = insert_list(3, :user)

      test_table_rows_count(conn, ~p"/admin/users", Enum.count(users))
      test_show_action_redirect(conn, ~p"/admin/users", users)
      test_edit_action_redirect(conn, ~p"/admin/users", users)
    end
  end

  describe "user authorization (admin cannot be soft-deleted)" do
    test "delete button rendered for regular users", %{conn: conn} do
      user = insert(:user, %{role: :user})
      test_action_available(conn, ~p"/admin/users", user, "Delete")
    end

    test "delete button NOT rendered for admin users", %{conn: conn} do
      admin = insert(:user, %{role: :admin})
      test_action_not_available(conn, ~p"/admin/users", admin, "Delete")
    end
  end
end
