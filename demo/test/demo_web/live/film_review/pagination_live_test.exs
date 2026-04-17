defmodule DemoWeb.Live.FilmReview.PaginationLiveTest do
  use DemoWeb.ConnCase, async: false

  import Demo.EctoFactory

  # Film reviews use default per_page_default: 15, per_page_options: [15, 50, 100]

  describe "pagination" do
    test "paginates items with default per_page", %{conn: conn} do
      insert_list(20, :film_review)

      conn
      |> visit(~p"/admin/film-reviews")
      |> assert_has("table tbody tr", count: 15)
      |> assert_has("div", text: "Items 1 to 15 (20 total)", exact: true)
    end

    test "navigates to page 2 via URL params", %{conn: conn} do
      insert_list(20, :film_review)

      params = %{"page" => "2"}

      conn
      |> visit(~p"/admin/film-reviews?#{params}")
      |> assert_has("table tbody tr", count: 5)
      |> assert_has("div", text: "Items 16 to 20 (20 total)", exact: true)
    end
  end

  describe "invalid pagination params" do
    test "invalid page falls back to page 1", %{conn: conn} do
      insert_list(3, :film_review)

      params = %{"page" => "invalid"}

      conn
      |> visit(~p"/admin/film-reviews?#{params}")
      |> assert_has("table tbody tr", count: 3)
      |> assert_has("div", text: "Items 1 to 3 (3 total)", exact: true)
    end

    test "page beyond total pages is clamped to last page", %{conn: conn} do
      insert_list(20, :film_review)

      params = %{"page" => "999"}

      conn
      |> visit(~p"/admin/film-reviews?#{params}")
      |> assert_has("table tbody tr", count: 5)
      |> assert_has("div", text: "Items 16 to 20 (20 total)", exact: true)
    end
  end
end
