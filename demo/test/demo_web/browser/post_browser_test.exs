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
      |> press("#filter-dropdown-menu [id^=multi-select-][id$=-trigger]", "Enter")
      |> assert_has("#filter-dropdown-menu input[name='filters[user_id][]']", count: 3)
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

    test "a11y with the tags dropdown open", %{conn: conn} do
      insert_list(3, :tag)

      conn
      |> visit(~p"/admin/posts/new")
      |> assert_has("body .phx-connected")
      |> press("#has-many-dropdown-tags-trigger", "Enter")
      |> assert_has("#has-many-dropdown-tags-menu input[name='change[tags][]']", count: 3)
      |> assert_a11y()
      |> evaluate("document.documentElement.dataset.theme = 'dark'")
      |> assert_a11y()
    end

    test "keeps the options of the closed tags dropdown out of the tab order", %{conn: conn} do
      insert_list(3, :tag)
      focus_in_menu = "document.activeElement.closest('#has-many-dropdown-tags-menu') !== null"

      conn
      |> visit(~p"/admin/posts/new")
      |> assert_has("body .phx-connected")
      |> press("#has-many-dropdown-tags-trigger", "Tab")
      |> evaluate(focus_in_menu, &refute/1)
      |> press("#has-many-dropdown-tags-trigger", "Enter")
      |> press("#has-many-dropdown-tags-trigger", "Tab")
      |> evaluate(focus_in_menu, &assert/1)
      |> press("#has-many-dropdown-tags-trigger", "Enter")
      |> press("#has-many-dropdown-tags-trigger", "Tab")
      |> evaluate(focus_in_menu, &refute/1)
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
