defmodule Backpex.E2E.KeyboardTest do
  use Backpex.E2ECase, async: true

  alias Backpex.Test.Product
  alias Backpex.Test.Repo
  alias Fluffy.Playwright.Keyboard

  describe "filters" do
    test "applies a filter preset with the keyboard", %{session: session} do
      insert_list(3, :post)
      over_100 = by_role(by_css("#filter-dropdown-menu"), :button, name: "Over 100")

      session
      |> visit(~p"/admin/posts")
      |> press(by_css("#filter-dropdown-trigger"), "Enter")
      |> assert_has(over_100)
      |> press(by_css(~s|input[name="filters[likes][end]"]|), "Tab")
      |> assert(focused(over_100))
      |> Keyboard.press("Enter")
      |> assert_has(by_role(:button, name: "Clear Likes filter"))
      |> assert(page_url(&(URI.decode_query(&1.query || "")["filters[likes][start]"] == "100")))
    end
  end

  describe "has many dropdown" do
    test "keeps the options of the closed dropdown out of the tab order", %{session: session} do
      insert_list(3, :tag)
      trigger = by_css("#has-many-dropdown-tags-trigger")
      focus_in_menu = by_css("#has-many-dropdown-tags-menu:focus-within")

      session
      |> visit(~p"/admin/posts/new")
      |> assert(attribute(trigger, "aria-expanded", "false"))
      |> press(trigger, "Tab")
      |> assert(count(focus_in_menu, 0))
      |> press(trigger, "Enter")
      |> assert(attribute(trigger, "aria-expanded", "true"))
      |> press(trigger, "Tab")
      |> assert(count(focus_in_menu, 1))
      |> press(trigger, "Enter")
      |> assert(attribute(trigger, "aria-expanded", "false"))
      |> press(trigger, "Tab")
      |> assert(count(focus_in_menu, 0))
    end

    test "selects and deselects all options with the keyboard", %{session: session} do
      insert_list(3, :tag)
      trigger = by_css("#has-many-dropdown-tags-trigger")
      tags = by_css("#has-many-tags")
      checked_tags = by_css(tags, "input[name='change[tags][]']:checked")
      select_all = by_role(tags, :button, name: "Select all", exact: true)
      deselect_all = by_role(tags, :button, name: "Deselect all", exact: true)

      # "Select all" sends an event to the server, so it needs the connected LiveView that `visit` waits for. The focus
      # assertions retry, since the buttons are patched after each event.
      session
      |> visit(~p"/admin/posts/new")
      |> press(trigger, "Enter")
      |> assert(attribute(trigger, "aria-expanded", "true"))
      |> press(by_role(by_css("#has-many-dropdown-tags-menu"), :searchbox), "Tab")
      |> assert(focused(select_all))
      |> press(select_all, "Enter")
      |> assert(count(checked_tags, 3))
      |> assert(focused(deselect_all))
      |> press(deselect_all, "Space")
      |> assert(count(checked_tags, 0))
      |> assert(focused(select_all))
    end
  end

  describe "inline crud" do
    test "removes rows with the keyboard", %{session: session} do
      short_links = [
        build(:short_link, url: "https://example.com/first"),
        build(:short_link, url: "https://example.com/second")
      ]

      product = insert(:product, short_links: short_links)
      url_input = fn index -> by_css("input[type=text][name='change[short_links][#{index}][url]']") end
      delete_first_entry = by_role(:button, name: "Delete entry 1", exact: true)

      session
      |> visit(~p"/admin/products/#{product.id}/edit")
      |> press(url_input.(0), "Tab")
      |> assert(focused(delete_first_entry))
      |> press(delete_first_entry, "Enter")
      |> refute_has(url_input.(1))
      |> assert(value(url_input.(0), "https://example.com/second"))
      |> assert(focused(delete_first_entry))
      |> press(delete_first_entry, "Space")
      |> refute_has(url_input.(0))
      |> assert(focused(by_role(:checkbox, name: "Add entry", exact: true)))
      |> assert_a11y()
      |> click(by_role(:button, name: "Save", exact: true))
      |> assert(page_url(~p"/admin/products"))

      assert %{short_links: []} = Product |> Repo.get!(product.id) |> Repo.preload(:short_links)
    end
  end
end
