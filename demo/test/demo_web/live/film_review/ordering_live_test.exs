defmodule DemoWeb.Live.FilmReview.OrderingLiveTest do
  use DemoWeb.ConnCase, async: false

  import Demo.EctoFactory
  import Phoenix.LiveViewTest

  # Film reviews use default init_order: %{by: :id, direction: :asc}

  describe "default ordering" do
    test "orders by id ascending by default", %{conn: conn} do
      insert(:film_review, title: "First Review")
      insert(:film_review, title: "Second Review")
      insert(:film_review, title: "Third Review")

      conn
      |> visit(~p"/admin/film-reviews")
      |> assert_has("table tbody tr", count: 3)
      |> assert_has("table tbody tr:first-child td", text: "First Review")
      |> assert_has("table tbody tr:last-child td", text: "Third Review")
    end
  end

  describe "ordering via URL params" do
    test "orders by title ascending", %{conn: conn} do
      insert(:film_review, title: "Cherry")
      insert(:film_review, title: "Apple")
      insert(:film_review, title: "Banana")

      params = %{"order_by" => "title", "order_direction" => "asc"}

      conn
      |> visit(~p"/admin/film-reviews?#{params}")
      |> assert_has("table tbody tr", count: 3)
      |> assert_has("table tbody tr:first-child td", text: "Apple")
      |> assert_has("table tbody tr:last-child td", text: "Cherry")
    end

    test "orders by title descending", %{conn: conn} do
      insert(:film_review, title: "Cherry")
      insert(:film_review, title: "Apple")
      insert(:film_review, title: "Banana")

      params = %{"order_by" => "title", "order_direction" => "desc"}

      conn
      |> visit(~p"/admin/film-reviews?#{params}")
      |> assert_has("table tbody tr", count: 3)
      |> assert_has("table tbody tr:first-child td", text: "Cherry")
      |> assert_has("table tbody tr:last-child td", text: "Apple")
    end
  end

  describe "invalid ordering params" do
    test "falls back to default order_by for invalid order_by field", %{conn: conn} do
      insert(:film_review, title: "First Review")
      insert(:film_review, title: "Second Review")
      insert(:film_review, title: "Third Review")

      params = %{"order_by" => "nonexistent_field", "order_direction" => "asc"}

      conn
      |> visit(~p"/admin/film-reviews?#{params}")
      |> assert_has("table tbody tr", count: 3)
      |> assert_has("table tbody tr:first-child td", text: "First Review")
      |> assert_has("table tbody tr:last-child td", text: "Third Review")
    end

    test "falls back to default direction for invalid order_direction", %{conn: conn} do
      insert(:film_review, title: "Cherry")
      insert(:film_review, title: "Apple")
      insert(:film_review, title: "Banana")

      params = %{"order_by" => "title", "order_direction" => "INVALID"}

      conn
      |> visit(~p"/admin/film-reviews?#{params}")
      |> assert_has("table tbody tr", count: 3)
      # order_by=title is valid, direction falls back to default: asc
      |> assert_has("table tbody tr:first-child td", text: "Apple")
      |> assert_has("table tbody tr:last-child td", text: "Cherry")
    end
  end

  describe "ordering via column header click" do
    test "clicking Title column orders by title ascending", %{conn: conn} do
      insert(:film_review, title: "Cherry")
      insert(:film_review, title: "Apple")
      insert(:film_review, title: "Banana")

      conn
      |> visit(~p"/admin/film-reviews")
      |> unwrap(fn view ->
        view
        |> element("a", "Title")
        |> render_click()
      end)
      |> assert_has("table tbody tr:first-child td", text: "Apple")
      |> assert_has("table tbody tr:last-child td", text: "Cherry")
    end
  end
end
