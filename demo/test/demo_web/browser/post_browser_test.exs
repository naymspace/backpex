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

    test "selects and deselects all tags with the keyboard", %{conn: conn} do
      insert_list(3, :tag)
      checked_tags = "#has-many-tags input[name='change[tags][]']:checked"

      conn
      |> visit(~p"/admin/posts/new")
      |> press("#has-many-dropdown-tags-trigger", "Enter")
      |> press("#has-many-dropdown-tags-menu input[type=search]", "Tab")
      |> evaluate("document.activeElement.textContent.trim()", &assert(&1 == "Select all"))
      |> press("#has-many-tags button:has-text('Select all')", "Enter")
      |> assert_has(checked_tags, count: 3)
      |> evaluate("document.activeElement.textContent.trim()", &assert(&1 == "Deselect all"))
      |> press("#has-many-tags button:has-text('Deselect all')", "Space")
      |> refute_has(checked_tags)
      |> evaluate("document.activeElement.textContent.trim()", &assert(&1 == "Select all"))
    end
  end
end
