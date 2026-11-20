defmodule Backpex.E2E.SelectFieldsTest do
  use Backpex.E2ECase, async: true

  alias Backpex.Test.Address
  alias Backpex.Test.Post
  alias Backpex.Test.Repo
  alias Backpex.Test.Sample

  # The fields and filters that render `Backpex.HTML.Combobox.combobox/1`. `Backpex.E2E.ComboboxTest` covers the
  # combobox itself; these tests cover what the fields add to it and that a selection reaches the server.

  defp trigger(id), do: "##{id}-trigger"
  defp search(id), do: "##{id}-search"
  defp options(id), do: "##{id}-listbox [role=option]"
  defp option(id, value), do: "##{id}-listbox [role=option][data-value='#{value}']"
  defp badges(id), do: "##{id} [data-part=badge]"

  defp open(conn, id) do
    conn
    |> click(trigger(id))
    |> assert_has("#{trigger(id)}[aria-expanded=true]")
  end

  describe "multi select field" do
    test "selects, searches and deselects in the browser and submits the selection", %{conn: conn} do
      id = "resource-form_users"

      conn
      |> visit(~p"/admin/users/invite/resource-action")
      |> assert_has("body .phx-connected")
      |> open(id)
      |> assert_has(options(id), count: 2)
      |> click("##{id} [data-part=select-all-button]")
      |> assert_has(badges(id), count: 2)
      |> assert_has("##{id} [data-part=selected-count]", text: "2", exact: true)
      |> click("##{id} [data-part=deselect-all-button]")
      |> refute_has(badges(id))
      |> assert_has("##{id} [data-part=selected-count]", text: "0", exact: true)
      # The search filters the options in the browser.
      |> type(search(id), "bo")
      |> assert_has(options(id), count: 1)
      |> click(option(id, "user_id_bob"))
      |> assert_has("#{badges(id)} [data-part=badge-label]", text: "Bob", exact: true)
      |> press(search(id), "Escape")
      |> assert_has("#{trigger(id)}[aria-expanded=false]")
      |> fill_in("Text", with: "Hello")
      |> click("#form-action-save")
      |> assert_has("div", text: "An email has been successfully sent to the specified users.")
    end
  end

  describe "has many field" do
    test "loads more options, searches them on the server and saves the selection", %{conn: conn} do
      # The field loads 10 options at a time.
      tags = for number <- 1..12, do: insert(:tag, name: "Topic #{String.pad_leading(to_string(number), 2, "0")}")
      post = insert(:post, tags: [])
      id = "resource-form_tags"

      conn
      |> visit(~p"/admin/posts/#{post.id}/edit")
      |> assert_has("body .phx-connected")
      |> open(id)
      |> assert_has(options(id), count: 10)
      |> click("##{id}-popup button", "Show more")
      |> assert_has(options(id), count: 12)
      |> refute_has("##{id}-popup button", text: "Show more")
      |> assert_has("#{trigger(id)}[aria-expanded=true]")
      |> click(option(id, Enum.at(tags, 0).id))
      |> assert_has(badges(id), count: 1)
      |> type(search(id), "Topic 12")
      |> assert_has(options(id), count: 1)
      # The selected tag is not among the search results, but stays selected.
      |> assert_has("#{badges(id)} [data-part=badge-label]", text: "Topic 01", exact: true)
      |> click(option(id, Enum.at(tags, 11).id))
      |> assert_has(badges(id), count: 2)
      |> press(search(id), "Escape")
      |> assert_has("#{trigger(id)}[aria-expanded=false]")
      |> click("#form-action-save")
      |> assert_path(~p"/admin/posts")

      saved = Post |> Repo.get!(post.id) |> Repo.preload(:tags) |> Map.fetch!(:tags)
      assert saved |> Enum.map(& &1.name) |> Enum.sort() == ["Topic 01", "Topic 12"]
    end
  end

  describe "select field" do
    test "searches its options and saves the selected one", %{conn: conn} do
      id = "resource-form_country"

      conn
      |> visit(~p"/admin/addresses/new")
      |> assert_has("body .phx-connected")
      # Without a prompt it selects its first option, like a native select.
      |> assert_has("##{id} [data-part=value-label]", text: "Germany", exact: true)
      |> refute_has("##{id} [data-part=clear]")
      |> fill_in("Street Name", with: "Main Street 1")
      |> fill_in("Zip Code", with: "12345")
      |> fill_in("City", with: "Toronto")
      |> open(id)
      |> assert_has(options(id), count: 5)
      |> type(search(id), "can")
      |> assert_has(options(id), count: 1)
      |> press(search(id), "Enter")
      |> assert_has("#{trigger(id)}[aria-expanded=false]")
      |> assert_has("##{id} [data-part=value-label]", text: "Canada", exact: true)
      |> click("#form-action-save")
      |> assert_path(~p"/admin/addresses")

      assert %Address{country: :ca} = Repo.get_by!(Address, street: "Main Street 1")
    end

    test "saves a selection and a cleared selection on the index view", %{conn: conn} do
      sample = insert(:sample, select: :one)
      id = "index-form-input-select-#{sample.id}"

      conn
      |> visit(~p"/admin/index-edit-samples")
      |> assert_has("body .phx-connected")
      |> assert_has("##{id} [data-part=value-label]", text: "One", exact: true)
      |> open(id)
      |> click(option(id, "two"))
      |> assert_has("##{id} [data-part=value-label]", text: "Two", exact: true)
      |> assert_has("#{trigger(id)}[aria-expanded=false]")
      |> evaluate("new Promise((resolve) => setTimeout(resolve, 200))")
      |> tap(fn _conn -> assert Repo.get!(Sample, sample.id).select == :two end)
      # The field has a prompt, so the selection can be cleared.
      |> click("##{id} [data-part=clear]")
      |> assert_has("##{id} [data-part=placeholder]", text: "Choose one", exact: true)
      |> evaluate("new Promise((resolve) => setTimeout(resolve, 200))")
      |> tap(fn _conn -> assert Repo.get!(Sample, sample.id).select == nil end)
    end
  end

  describe "has many through field" do
    test "selects the related record in the modal", %{conn: conn} do
      [_address, other_address] = for street <- ["Elm Street", "Oak Street"], do: insert(:address, street: street)
      id = "resource-form_users_addresses_0_address_id"

      conn
      |> visit(~p"/admin/users/new")
      |> assert_has("body .phx-connected")
      |> click_button("Attach Address")
      |> assert_has("#edit-relational-modal-0[open]")
      |> assert_has("##{id} [data-part=placeholder]", text: "Choose Address ...", exact: true)
      |> open(id)
      |> type(search(id), "oak")
      |> assert_has(options(id), count: 1)
      |> click(option(id, other_address.id))
      |> assert_has("##{id} [data-part=value-label]", text: "Oak Street", exact: true)
      # The popup closes, the modal stays open.
      |> assert_has("#{trigger(id)}[aria-expanded=false]")
      |> assert_has("#edit-relational-modal-0[open]")
      |> click_button("Apply")
      |> assert_has("td", text: "Oak Street")
    end
  end

  describe "filters" do
    test "filter by the selected options while the filter dropdown and the combobox stay open", %{conn: conn} do
      [post, other_post, _third_post] = insert_list(3, :post)
      id = "filter-form_user_id"

      conn
      |> visit(~p"/admin/posts")
      |> assert_has("body .phx-connected")
      |> assert_has("table tbody tr", count: 3)
      |> click("#filter-dropdown-trigger")
      |> open(id)
      # The menu of the dropdown is focusable; a click on an option must not move the focus to it.
      |> click(option(id, post.user_id))
      |> assert_has("table tbody tr", count: 1)
      |> assert_has(badges(id), count: 1)
      |> assert_has("#{trigger(id)}[aria-expanded=true]")
      |> assert_has("#filter-dropdown.dropdown-open")
      |> click(option(id, other_post.user_id))
      |> assert_has("table tbody tr", count: 2)
      |> assert_has(badges(id), count: 2)
      |> evaluate("decodeURIComponent(window.location.search)", fn search ->
        assert search =~ "filters[user_id][]=#{post.user_id}"
        assert search =~ "filters[user_id][]=#{other_post.user_id}"
      end)
      |> press(search(id), "Escape")
      # Escape closes the combobox, not the filter dropdown.
      |> assert_has("#{trigger(id)}[aria-expanded=false]")
      |> assert_has("#filter-dropdown.dropdown-open")
    end

    test "filter by the option of the select filter and clear it", %{conn: conn} do
      [post | _posts] = insert_list(3, :post)
      id = "filter-form_category_id"

      conn
      |> visit(~p"/admin/posts")
      |> assert_has("body .phx-connected")
      |> click("#filter-dropdown-trigger")
      |> open(id)
      |> click(option(id, post.category_id))
      |> assert_has("table tbody tr", count: 1)
      |> assert_has("#{trigger(id)}[aria-expanded=false]")
      |> assert_has("#filter-dropdown.dropdown-open")
      |> click("##{id} [data-part=clear]")
      |> assert_has("table tbody tr", count: 3)
      |> assert_has("##{id} [data-part=placeholder]", text: "Select category ...", exact: true)
    end
  end
end
