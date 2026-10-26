defmodule Backpex.E2E.KeyboardTest do
  use Backpex.E2ECase, async: true

  alias Backpex.Test.Product
  alias Backpex.Test.Repo

  describe "filters" do
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

  describe "has many dropdown" do
    test "keeps the options of the closed dropdown out of the tab order", %{conn: conn} do
      insert_list(3, :tag)
      focus_in_menu = "document.activeElement.closest('#has-many-dropdown-tags-menu') !== null"

      conn
      |> visit(~p"/admin/posts/new")
      |> assert_has("body .phx-connected")
      |> assert_has("#has-many-dropdown-tags-trigger[aria-expanded=false]")
      |> press("#has-many-dropdown-tags-trigger", "Tab")
      |> evaluate(focus_in_menu, &refute/1)
      |> press("#has-many-dropdown-tags-trigger", "Enter")
      |> assert_has("#has-many-dropdown-tags-trigger[aria-expanded=true]")
      |> press("#has-many-dropdown-tags-trigger", "Tab")
      |> evaluate(focus_in_menu, &assert/1)
      |> press("#has-many-dropdown-tags-trigger", "Enter")
      |> assert_has("#has-many-dropdown-tags-trigger[aria-expanded=false]")
      |> press("#has-many-dropdown-tags-trigger", "Tab")
      |> evaluate(focus_in_menu, &refute/1)
    end

    test "selects and deselects all options with the keyboard", %{conn: conn} do
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
      |> press(url_input.(0), "Tab")
      |> evaluate("document.activeElement.getAttribute('aria-label')", &assert(&1 == "Delete entry 1"))
      |> press("button[aria-label='Delete entry 1']", "Enter")
      |> refute_has(url_input.(1))
      |> assert_has(url_input.(0), value: "https://example.com/second")
      |> evaluate("document.activeElement.getAttribute('aria-label')", &assert(&1 == "Delete entry 1"))
      |> press("button[aria-label='Delete entry 1']", "Space")
      |> refute_has(url_input.(0))
      |> evaluate("document.activeElement.getAttribute('aria-label')", &assert(&1 == "Add entry"))
      |> assert_a11y()
      |> click_button("Save")
      |> assert_path(~p"/admin/products")

      assert %{short_links: []} = Product |> Repo.get!(product.id) |> Repo.preload(:short_links)
    end
  end
end
