defmodule DemoWeb.Browser.FilmReviewBrowserTest do
  use PhoenixTest.Playwright.Case, async: false
  use DemoWeb, :verified_routes
  use DemoWeb.A11yAssertions

  import Demo.EctoFactory

  @moduletag :playwright

  describe "film-reviews index" do
    test "a11y", %{conn: conn} do
      insert_list(10, :film_review)

      conn
      |> visit(~p"/admin/film-reviews")
      |> assert_a11y()
    end
  end

  describe "film-reviews show" do
    test "a11y", %{conn: conn} do
      film_review = insert(:film_review)

      conn
      |> visit(~p"/admin/film-reviews/#{film_review.id}/show")
      |> assert_a11y()
    end
  end

  describe "film-reviews edit" do
    test "a11y", %{conn: conn} do
      film_review = insert(:film_review)

      conn
      |> visit(~p"/admin/film-reviews/#{film_review.id}/edit")
      |> assert_a11y()
    end
  end

  describe "film-reviews new" do
    test "a11y", %{conn: conn} do
      conn
      |> visit(~p"/admin/film-reviews/new")
      |> assert_a11y()
    end
  end
end
