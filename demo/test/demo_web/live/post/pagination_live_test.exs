defmodule DemoWeb.Live.Post.PaginationLiveTest do
  use DemoWeb.ConnCase, async: false

  import Demo.EctoFactory

  # Posts use default per_page_default: 15, per_page_options: [15, 50, 100]
  # Posts have a default published filter

  describe "pagination" do
    test "paginates items with default per_page", %{conn: conn} do
      insert_list(20, :post, published: true)

      conn
      |> visit(~p"/admin/posts")
      |> assert_has("table tbody tr", count: 15)
    end

    test "navigates to page 2 via URL params", %{conn: conn} do
      insert_list(20, :post, published: true)

      params = %{"page" => "2"}

      conn
      |> visit(~p"/admin/posts?#{params}")
      |> assert_has("table tbody tr", count: 5)
    end

    test "changes per_page via URL params", %{conn: conn} do
      insert_list(20, :post, published: true)

      params = %{"per_page" => "50"}

      conn
      |> visit(~p"/admin/posts?#{params}")
      |> assert_has("table tbody tr", count: 20)
    end
  end

  describe "invalid pagination params" do
    test "invalid page falls back to page 1", %{conn: conn} do
      insert_list(3, :post, published: true)

      params = %{"page" => "invalid"}

      conn
      |> visit(~p"/admin/posts?#{params}")
      |> assert_has("table tbody tr", count: 3)
    end

    test "negative page falls back to page 1", %{conn: conn} do
      insert_list(3, :post, published: true)

      params = %{"page" => "-5"}

      conn
      |> visit(~p"/admin/posts?#{params}")
      |> assert_has("table tbody tr", count: 3)
    end

    test "page beyond total pages is clamped to last page", %{conn: conn} do
      insert_list(20, :post, published: true)

      params = %{"page" => "999"}

      conn
      |> visit(~p"/admin/posts?#{params}")
      |> assert_has("table tbody tr", count: 5)
    end

    test "invalid per_page falls back to default", %{conn: conn} do
      insert_list(3, :post, published: true)

      params = %{"per_page" => "invalid"}

      conn
      |> visit(~p"/admin/posts?#{params}")
      |> assert_has("table tbody tr", count: 3)
    end
  end
end
