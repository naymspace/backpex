defmodule DemoWeb.Browser.FilmReviewBrowserTest do
  use DemoWeb.BrowserCase, async: false
  use DemoWeb, :verified_routes
  use DemoWeb.A11yAssertions

  import Demo.EctoFactory

  @moduletag :playwright

  describe "film-reviews index" do
    test "a11y", %{session: session} do
      insert_list(10, :film_review)

      session
      |> visit(~p"/admin/film-reviews")
      |> assert_a11y()
    end

    test "a11y with the pagination placeholder", %{session: session} do
      insert_list(100, :film_review)

      session
      |> visit(~p"/admin/film-reviews")
      |> assert_has(by_css(".join-item") |> filter(has_text: "..."))
      |> assert_a11y()
    end
  end

  describe "film-reviews show" do
    test "a11y", %{session: session} do
      film_review = insert(:film_review)

      session
      |> visit(~p"/admin/film-reviews/#{film_review.id}/show")
      |> assert_a11y()
    end
  end

  describe "film-reviews edit" do
    test "a11y", %{session: session} do
      film_review = insert(:film_review)

      session
      |> visit(~p"/admin/film-reviews/#{film_review.id}/edit")
      |> assert_a11y()
    end
  end

  describe "film-reviews new" do
    test "a11y", %{session: session} do
      session
      |> visit(~p"/admin/film-reviews/new")
      |> assert_a11y()
    end
  end
end
