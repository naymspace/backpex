defmodule DemoWeb.Live.FilmReview.IndexLiveTest do
  use DemoWeb.ConnCase, async: false

  import Demo.EctoFactory
  import Phoenix.LiveViewTest

  describe "film reviews live resource index" do
    test "is rendered", %{conn: conn} do
      insert_list(3, :film_review)

      conn
      |> visit(~p"/admin/film-reviews")
      |> assert_has("h1", text: "Film Reviews", exact: true)
      |> assert_has("button", text: "New Film Review", exact: true)
      |> assert_has("table tbody tr", count: 3)
    end

    test "shows full-text search info alert", %{conn: conn} do
      insert(:film_review)

      conn
      |> visit(~p"/admin/film-reviews")
      |> assert_has("div", text: "This resource uses the full-text search functionality")
    end

    test "full-text search returns matching results", %{conn: conn} do
      insert(:film_review, %{title: "The Matrix", overview: "A sci-fi classic about reality"})
      insert(:film_review, %{title: "Inception", overview: "Dreams within dreams"})

      conn
      |> visit(~p"/admin/film-reviews")
      |> assert_has(".table tbody tr", count: 2)
      |> unwrap(fn view ->
        view
        |> form("#index-search-form", index_search: %{value: "Matrix"})
        |> render_change()
      end)
      |> assert_has("table tbody tr", count: 1)
      |> assert_has("tr", text: "The Matrix")
      |> refute_has("tr", text: "Inception")
    end

    test "no delete action available (can? returns false)", %{conn: conn} do
      film_review = insert(:film_review)

      conn
      |> visit(~p"/admin/film-reviews")
      # Delete button should not be present for this resource
      |> refute_has("button[aria-label='Delete'][phx-value-item-id='#{film_review.id}']")
    end

    test "show action is available", %{conn: conn} do
      film_review = insert(:film_review)

      conn
      |> visit(~p"/admin/film-reviews")
      |> assert_has("#item-action-show-#{film_review.id}")
    end

    test "edit action is available", %{conn: conn} do
      film_review = insert(:film_review)

      conn
      |> visit(~p"/admin/film-reviews")
      |> assert_has("#item-action-edit-#{film_review.id}")
    end
  end

  describe "film reviews show view" do
    test "no delete button on show view", %{conn: conn} do
      film_review = insert(:film_review, %{title: "Test Film"})

      conn
      |> visit(~p"/admin/film-reviews/#{film_review.id}/show")
      |> assert_has("dd", text: "Test Film")
      |> refute_has("#item-action-delete")
    end
  end
end
