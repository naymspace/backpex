defmodule DemoWeb.Browser.PostBrowserTest do
  use PhoenixTest.Playwright.Case, async: false
  use DemoWeb, :verified_routes
  use DemoWeb.A11yAssertions

  import Demo.EctoFactory

  @moduletag :playwright

  describe "posts index" do
    test "a11y", %{conn: conn} do
      insert_list(10, :post)

      conn
      |> visit(~p"/admin/posts")
      |> assert_a11y()
    end

    test "applies a filter preset with the keyboard", %{conn: conn} do
      insert_list(3, :post)

      conn
      |> visit(~p"/admin/posts")
      |> assert_has("body .phx-connected")
      |> press("#filter-dropdown-trigger", "Enter")
      |> assert_has("#filter-dropdown-menu button", text: "Over 100")
      |> press(~s|input[name="filters[likes][end]"]|, "Tab")
      |> assert_has("button[type=button]:focus", text: "Over 100")
      |> press("button:focus", "Enter")
      |> assert_has(~s|button[aria-label="Clear Likes filter"]|)
      |> evaluate("decodeURIComponent(window.location.search)", fn search ->
        assert search =~ "filters[likes][start]=100"
      end)
    end
  end

  describe "posts show" do
    test "a11y", %{conn: conn} do
      post = insert(:post)

      conn
      |> visit(~p"/admin/posts/#{post.id}/show")
      |> assert_a11y()
    end
  end

  describe "posts edit" do
    test "a11y", %{conn: conn} do
      post = insert(:post)

      conn
      |> visit(~p"/admin/posts/#{post.id}/edit")
      |> assert_a11y()
    end
  end

  describe "posts new" do
    test "a11y", %{conn: conn} do
      conn
      |> visit(~p"/admin/posts/new")
      |> assert_a11y()
    end
  end
end
