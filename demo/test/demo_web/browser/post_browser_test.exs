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

    test "a11y with the filter dropdown and its multi select open", %{conn: conn} do
      insert_list(3, :post)

      conn
      |> visit(~p"/admin/posts")
      |> assert_has("body .phx-connected")
      |> press("#filter-dropdown-trigger", "Enter")
      |> press("#filter-form_user_id-trigger", "Enter")
      |> assert_has("#filter-form_user_id-listbox [role=option]", count: 3)
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

    test "a11y with the tags combobox open", %{conn: conn} do
      insert_list(3, :tag)

      conn
      |> visit(~p"/admin/posts/new")
      |> assert_has("body .phx-connected")
      |> press("#resource-form_tags-trigger", "Enter")
      |> assert_has("#resource-form_tags-listbox [role=option]", count: 3)
      |> assert_a11y()
    end
  end
end
