defmodule DemoWeb.Browser.PostBrowserTest do
  use DemoWeb.BrowserCase, async: false
  use DemoWeb, :verified_routes
  use DemoWeb.A11yAssertions

  import Demo.EctoFactory

  alias Playwright.Page

  @moduletag :playwright

  describe "posts index" do
    test "a11y", %{conn: conn} do
      insert_list(10, :post)

      conn
      |> visit(~p"/admin/posts")
      |> assert_a11y()
    end

    test "a11y with the filter dropdown and its multi select open", %{conn: conn} do
      insert_list(3, :post)

      conn
      |> visit(~p"/admin/posts")
      |> assert_has("body .phx-connected")
      |> unwrap(&Page.press!(&1, "#filter-dropdown-trigger", "Enter"))
      |> unwrap(&Page.press!(&1, "#filter-dropdown-menu [id^=multi-select-][id$=-trigger]", "Enter"))
      |> assert_has("#filter-dropdown-menu input[name='filters[user_id][]']:visible", count: 3)
      |> assert_a11y()
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

    test "a11y with the tags dropdown open", %{conn: conn} do
      insert_list(3, :tag)

      conn
      |> visit(~p"/admin/posts/new")
      |> assert_has("body .phx-connected")
      |> unwrap(&Page.press!(&1, "#has-many-dropdown-tags-trigger", "Enter"))
      |> assert_has("#has-many-dropdown-tags-menu input[name='change[tags][]']:visible", count: 3)
      |> assert_a11y()
      |> unwrap(&Page.evaluate!(&1, "document.documentElement.dataset.theme = 'dark'"))
      |> assert_a11y()
    end
  end
end
