defmodule Backpex.E2E.KeyboardTest do
  use Backpex.E2ECase, async: true

  alias Backpex.Test.Product
  alias Backpex.Test.Repo
  alias Playwright.Page

  describe "filters" do
    test "applies a filter preset with the keyboard", %{conn: conn} do
      insert_list(3, :post)

      conn
      |> visit(~p"/admin/posts")
      |> assert_has("body .phx-connected")
      |> unwrap(&Page.press!(&1, "#filter-dropdown-trigger", "Enter"))
      |> assert_has("#filter-dropdown-menu button", text: "Over 100")
      |> unwrap(&Page.press!(&1, ~s|input[name="filters[likes][end]"]|, "Tab"))
      |> assert_has("button[type=button]:focus", text: "Over 100")
      |> unwrap(&Page.press!(&1, "button:focus", "Enter"))
      |> assert_has(~s|button[aria-label="Clear Likes filter"]|)
      |> unwrap(fn page ->
        search = Page.evaluate!(page, "decodeURIComponent(window.location.search)")
        assert search =~ "filters[likes][start]=100"
      end)
    end
  end

  describe "has many dropdown" do
    test "keeps the options of the closed dropdown out of the tab order", %{conn: conn} do
      insert_list(3, :tag)
      focus_in_menu = "document.activeElement.closest('#has-many-dropdown-tags-menu') !== null"

      conn
      |> visit(~p"/admin/posts/new")
      |> assert_has("body .phx-connected")
      |> assert_has("#has-many-dropdown-tags-trigger[aria-expanded=false]")
      |> unwrap(&Page.press!(&1, "#has-many-dropdown-tags-trigger", "Tab"))
      |> unwrap(&refute(Page.evaluate!(&1, focus_in_menu)))
      |> unwrap(&Page.press!(&1, "#has-many-dropdown-tags-trigger", "Enter"))
      |> assert_has("#has-many-dropdown-tags-trigger[aria-expanded=true]")
      |> unwrap(&Page.press!(&1, "#has-many-dropdown-tags-trigger", "Tab"))
      |> unwrap(&assert(Page.evaluate!(&1, focus_in_menu)))
      |> unwrap(&Page.press!(&1, "#has-many-dropdown-tags-trigger", "Enter"))
      |> assert_has("#has-many-dropdown-tags-trigger[aria-expanded=false]")
      |> unwrap(&Page.press!(&1, "#has-many-dropdown-tags-trigger", "Tab"))
      |> unwrap(&refute(Page.evaluate!(&1, focus_in_menu)))
    end

    test "selects and deselects all options with the keyboard", %{conn: conn} do
      insert_list(3, :tag)
      checked_tags = "#has-many-tags input[name='change[tags][]']:checked"

      # "Select all" sends an event to the server, so the LiveView has to be connected before the key presses. The focus
      # assertions retry, since the buttons are patched after each event.
      conn
      |> visit(~p"/admin/posts/new")
      |> assert_has("body .phx-connected")
      |> unwrap(&Page.press!(&1, "#has-many-dropdown-tags-trigger", "Enter"))
      |> assert_has("#has-many-dropdown-tags-trigger[aria-expanded=true]")
      |> unwrap(&Page.press!(&1, "#has-many-dropdown-tags-menu input[type=search]", "Tab"))
      |> assert_has("#has-many-tags button:focus", text: "Select all", exact: true)
      |> unwrap(&Page.press!(&1, "#has-many-tags button:has-text('Select all')", "Enter"))
      |> assert_has(checked_tags, count: 3)
      |> assert_has("#has-many-tags button:focus", text: "Deselect all", exact: true)
      |> unwrap(&Page.press!(&1, "#has-many-tags button:has-text('Deselect all')", "Space"))
      |> refute_has(checked_tags)
      |> assert_has("#has-many-tags button:focus", text: "Select all", exact: true)
    end
  end

  describe "inline crud" do
    test "removes rows with the keyboard", %{conn: conn} do
      short_links = [
        build(:short_link, url: "https://example.com/first"),
        build(:short_link, url: "https://example.com/second")
      ]

      product = insert(:product, short_links: short_links)
      url_input = fn index -> "input[type=text][name='change[short_links][#{index}][url]']" end

      conn
      |> visit(~p"/admin/products/#{product.id}/edit")
      |> assert_has("body .phx-connected")
      |> unwrap(&Page.press!(&1, url_input.(0), "Tab"))
      |> unwrap(&assert(Page.evaluate!(&1, "document.activeElement.getAttribute('aria-label')") == "Delete entry 1"))
      |> unwrap(&Page.press!(&1, "button[aria-label='Delete entry 1']", "Enter"))
      |> refute_has(url_input.(1))
      |> assert_has(url_input.(0), value: "https://example.com/second")
      |> unwrap(&assert(Page.evaluate!(&1, "document.activeElement.getAttribute('aria-label')") == "Delete entry 1"))
      |> unwrap(&Page.press!(&1, "button[aria-label='Delete entry 1']", "Space"))
      |> refute_has(url_input.(0))
      |> unwrap(&assert(Page.evaluate!(&1, "document.activeElement.getAttribute('aria-label')") == "Add entry"))
      |> assert_a11y()
      |> click_button("Save")
      |> assert_path(~p"/admin/products")

      assert %{short_links: []} = Product |> Repo.get!(product.id) |> Repo.preload(:short_links)
    end
  end
end
