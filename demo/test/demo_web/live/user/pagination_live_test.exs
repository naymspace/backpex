defmodule DemoWeb.Live.User.PaginationLiveTest do
  use DemoWeb.ConnCase, async: false

  import Demo.EctoFactory

  # Users use default per_page_default: 15, per_page_options: [15, 50, 100]

  describe "pagination" do
    test "paginates items with default per_page", %{conn: conn} do
      insert_list(20, :user)

      conn
      |> visit(~p"/admin/users")
      |> assert_has("table tbody tr", count: 15)
    end

    test "navigates to page 2 via URL params", %{conn: conn} do
      insert_list(20, :user)

      params = %{"page" => "2"}

      conn
      |> visit(~p"/admin/users?#{params}")
      |> assert_has("table tbody tr", count: 5)
    end

    test "changes per_page via URL params", %{conn: conn} do
      insert_list(20, :user)

      params = %{"per_page" => "50"}

      conn
      |> visit(~p"/admin/users?#{params}")
      |> assert_has("table tbody tr", count: 20)
    end
  end

  describe "invalid pagination params" do
    test "invalid page falls back to page 1", %{conn: conn} do
      insert_list(3, :user)

      params = %{"page" => "invalid"}

      conn
      |> visit(~p"/admin/users?#{params}")
      |> assert_has("table tbody tr", count: 3)
    end

    test "page beyond total pages is clamped to last page", %{conn: conn} do
      insert_list(20, :user)

      params = %{"page" => "999"}

      conn
      |> visit(~p"/admin/users?#{params}")
      |> assert_has("table tbody tr", count: 5)
    end
  end
end
