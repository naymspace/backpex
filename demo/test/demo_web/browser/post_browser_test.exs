defmodule DemoWeb.Browser.PostBrowserTest do
  use DemoWeb.BrowserCase, async: false
  use DemoWeb, :verified_routes
  use DemoWeb.A11yAssertions

  import Demo.EctoFactory

  @moduletag :playwright

  describe "posts index" do
    test "a11y", %{session: session} do
      insert_list(10, :post)

      session
      |> visit(~p"/admin/posts")
      |> assert_a11y()
    end

    test "a11y with the filter dropdown and its multi select open", %{session: session} do
      insert_list(3, :post)
      user_options = by_css("#filter-dropdown-menu input[name='filters[user_id][]']") |> filter(visible: true)

      session
      |> visit(~p"/admin/posts")
      |> press(by_css("#filter-dropdown-trigger"), "Enter")
      |> press(by_css("#filter-dropdown-menu [id^=multi-select-][id$=-trigger]"), "Enter")
      |> assert(count(user_options, 3))
      |> assert_a11y()
    end
  end

  describe "posts show" do
    test "a11y", %{session: session} do
      post = insert(:post)

      session
      |> visit(~p"/admin/posts/#{post.id}/show")
      |> assert_a11y()
    end
  end

  describe "posts edit" do
    test "a11y", %{session: session} do
      post = insert(:post)

      session
      |> visit(~p"/admin/posts/#{post.id}/edit")
      |> assert_a11y()
    end
  end

  describe "posts new" do
    test "a11y", %{session: session} do
      session
      |> visit(~p"/admin/posts/new")
      |> assert_a11y()
    end

    test "a11y with the tags dropdown open", %{session: session} do
      insert_list(3, :tag)
      tag_options = by_css("#has-many-dropdown-tags-menu input[name='change[tags][]']") |> filter(visible: true)

      session
      |> visit(~p"/admin/posts/new")
      |> press(by_css("#has-many-dropdown-tags-trigger"), "Enter")
      |> assert(count(tag_options, 3))
      |> assert_a11y()
      # Choosing a theme closes the tags dropdown, so it is opened again for the audit in dark mode.
      |> click(by_css("#backpex-theme-selector-trigger"))
      |> click(by_css("#backpex-theme-selector label") |> filter(has_text: "Dark"))
      |> assert(attribute(by_css("html"), "data-theme", "dark"))
      |> assert(attribute(by_css("#has-many-dropdown-tags-trigger"), "aria-expanded", "false"))
      |> press(by_css("#has-many-dropdown-tags-trigger"), "Enter")
      |> assert(count(tag_options, 3))
      |> assert_a11y()
    end
  end
end
