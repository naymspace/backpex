defmodule Backpex.Integration.Index.PaginationTest do
  use Backpex.ConnCase, async: true

  import Phoenix.LiveViewTest

  # Tags use the defaults `per_page_default: 15` and `per_page_options: [15, 50, 100]`.
  describe "pagination params" do
    test "shows the first page with the default page size", %{conn: conn} do
      insert_list(20, :tag)

      conn
      |> visit(~p"/admin/tags")
      |> assert_has("table tbody tr", count: 15)
      |> assert_has("div", text: "Items 1 to 15 (20 total)", exact: true)
    end

    test "shows the page of the page param", %{conn: conn} do
      insert_list(20, :tag)

      conn
      |> visit(~p"/admin/tags?#{%{"page" => "2"}}")
      |> assert_has("table tbody tr", count: 5)
      |> assert_has("div", text: "Items 16 to 20 (20 total)", exact: true)
    end

    test "uses the page size of the per_page param", %{conn: conn} do
      insert_list(20, :tag)

      conn
      |> visit(~p"/admin/tags?#{%{"per_page" => "50"}}")
      |> assert_has("table tbody tr", count: 20)
      |> assert_has("div", text: "Items 1 to 20 (20 total)", exact: true)
    end
  end

  describe "invalid pagination params" do
    for page <- ["invalid", "-5"] do
      test "fall back to the first page for page #{inspect(page)}", %{conn: conn} do
        insert_list(3, :tag)

        conn
        |> visit(~p"/admin/tags?#{%{"page" => unquote(page)}}")
        |> assert_has("table tbody tr", count: 3)
        |> assert_has("div", text: "Items 1 to 3 (3 total)", exact: true)
      end
    end

    test "clamp a page beyond the last page to the last page", %{conn: conn} do
      insert_list(20, :tag)

      conn
      |> visit(~p"/admin/tags?#{%{"page" => "999"}}")
      |> assert_has("table tbody tr", count: 5)
      |> assert_has("div", text: "Items 16 to 20 (20 total)", exact: true)
    end

    # "25" is a number, but not one of the `per_page_options`.
    for per_page <- ["invalid", "25"] do
      test "fall back to the default page size for per_page #{inspect(per_page)}", %{conn: conn} do
        insert_list(16, :tag)

        conn
        |> visit(~p"/admin/tags?#{%{"per_page" => unquote(per_page)}}")
        |> assert_has("table tbody tr", count: 15)
        |> assert_has("div", text: "Items 1 to 15 (16 total)", exact: true)
      end
    end
  end

  describe "page links" do
    for search <- ["R&D", "C# dev"] do
      test "keep the search #{inspect(search)} when navigating to page 2", %{conn: conn} do
        search = unquote(search)

        for i <- 1..20, do: insert(:post, title: "#{search} report #{i}")
        insert(:post, title: "Unrelated post")

        params = %{"search" => search, "filters" => %{"published" => ["published"]}}

        conn
        |> visit(~p"/admin/posts?#{params}")
        |> click_link(".join-item", "2")
        |> assert_path(~p"/admin/posts",
          query_params: %{
            "search" => search,
            "filters" => %{"published" => ["published"]},
            "filters_changed" => "false",
            "order_by" => "id",
            "order_direction" => "asc",
            "per_page" => "15",
            "page" => "2"
          }
        )
        |> assert_has("input[name='index_search[value]'][value='#{search}']")
        |> assert_has("table tbody tr", count: 5)
      end
    end
  end

  describe "ordering" do
    # The order link merges the new order into the current query options, so the page is kept, like the demo's
    # "ordering preserves pagination".
    test "keeps the current page", %{conn: conn} do
      insert_list(20, :product)

      conn
      |> visit(~p"/admin/products?#{%{"page" => "2", "order_by" => "name", "order_direction" => "asc"}}")
      |> assert_has("div", text: "Items 16 to 20 (20 total)", exact: true)
      |> unwrap(fn view ->
        view
        |> element("a", "Quantity")
        |> render_click()
      end)
      |> assert_has("div", text: "Items 16 to 20 (20 total)", exact: true)
      |> assert_has("table tbody tr", count: 5)
    end
  end
end
