defmodule Backpex.E2E.A11yTest do
  use Backpex.E2ECase, async: true

  # Every view of every LiveResource of the test app, so a markup change in Backpex that breaks accessibility fails here
  # even if no other test looks at that view. `{path, factory, primary key, views}`.
  @resources [
    {"/admin/users", :user, :id, [:index, :new, :show, :edit]},
    {"/admin/addresses", :address, :id, [:index, :new, :show, :edit]},
    {"/admin/products", :product, :id, [:index, :new, :show, :edit]},
    {"/admin/product-short-links", :product, :id, [:index, :show, :edit]},
    {"/admin/invoices", :invoice, :id, [:index]},
    {"/admin/film-reviews", :film_review, :id, [:index, :new, :show, :edit]},
    {"/admin/short-links", :short_link, :short_key, [:index, :new, :show, :edit]},
    {"/admin/samples", :sample, :id, [:index, :new, :show, :edit]},
    {"/admin/index-edit-samples", :sample, :id, [:index]},
    {"/admin/posts", :post, :id, [:index, :new, :show, :edit]},
    {"/admin/categories", :category, :id, [:index, :new, :show, :edit]},
    {"/admin/tags", :tag, :id, [:index, :new, :show, :edit]},
    {"/admin/notes", :note, :id, [:index, :new, :show, :edit]}
  ]

  for {path, factory, primary_key, views} <- @resources, view <- views do
    @tag path: path, factory: factory, primary_key: primary_key, view: view
    test "#{path} #{view}", %{conn: conn} = context do
      item = insert(context.factory)
      # Encoded like the router encodes a path segment: a space becomes `%20`, not `+`.
      id = item |> Map.fetch!(context.primary_key) |> to_string() |> URI.encode(&URI.char_unreserved?/1)

      path =
        case context.view do
          :index -> context.path
          :new -> "#{context.path}/new"
          :show -> "#{context.path}/#{id}/show"
          :edit -> "#{context.path}/#{id}/edit"
        end

      conn
      |> visit(path)
      |> assert_has("body .phx-connected")
      |> assert_a11y()
    end
  end

  test "the delete confirmation modal", %{conn: conn} do
    address = insert(:address)

    conn
    |> visit(~p"/admin/addresses")
    |> assert_has("body .phx-connected")
    |> click("#item-action-delete-#{address.id}")
    |> assert_has("#action-confirm-modal[open]")
    |> assert_a11y()
  end

  test "the filter dropdown with an open multi select and an open select", %{conn: conn} do
    [post | _posts] = insert_list(3, :post)

    conn
    |> visit(~p"/admin/posts")
    |> assert_has("body .phx-connected")
    |> press("#filter-dropdown-trigger", "Enter")
    |> press("#filter-form_user_id-trigger", "Enter")
    |> assert_has("#filter-form_user_id-listbox [role=option]", count: 3)
    |> click("#filter-form_user_id-listbox [role=option][data-value='#{post.user_id}']")
    |> assert_has("#filter-form_user_id [data-part=badge]", count: 1)
    |> assert_a11y()
    |> press("#filter-form_user_id-search", "Escape")
    |> press("#filter-form_category_id-trigger", "Enter")
    |> assert_has("#filter-form_category_id-trigger[aria-expanded=true]")
    |> assert_a11y()
  end

  test "an open has many combobox with a selection", %{conn: conn} do
    insert_list(3, :tag)

    conn
    |> visit(~p"/admin/posts/new")
    |> assert_has("body .phx-connected")
    |> press("#resource-form_tags-trigger", "Enter")
    |> assert_has("#resource-form_tags-listbox [role=option]", count: 3)
    |> click("#resource-form_tags-listbox [role=option]:first-child")
    |> assert_has("#resource-form_tags [data-part=badge]", count: 1)
    |> assert_a11y()
  end

  test "an open select with a search input and groups in light and dark mode", %{conn: conn} do
    conn
    |> visit(~p"/admin/addresses/new")
    |> assert_has("body .phx-connected")
    |> press("#resource-form_country-trigger", "Enter")
    |> assert_has("#resource-form_country-search:focus")
    |> assert_a11y()
    |> evaluate("document.documentElement.dataset.theme = 'dark'")
    |> assert_a11y()
  end

  test "an open index editable select", %{conn: conn} do
    sample = insert(:sample)

    conn
    |> visit(~p"/admin/index-edit-samples")
    |> assert_has("body .phx-connected")
    |> press("#index-form-input-select-#{sample.id}-trigger", "Enter")
    |> assert_has("#index-form-input-select-#{sample.id}-trigger[aria-expanded=true]")
    |> assert_a11y()
  end

  test "the select of a has many through field in its modal", %{conn: conn} do
    insert_list(2, :address)

    conn
    |> visit(~p"/admin/users/new")
    |> assert_has("body .phx-connected")
    |> click_button("Attach Address")
    |> assert_has("#edit-relational-modal-0[open]")
    |> click("#resource-form_users_addresses_0_address_id-trigger")
    |> assert_has("#resource-form_users_addresses_0_address_id-trigger[aria-expanded=true]")
    |> assert_has("#resource-form_users_addresses_0_address_id-search:focus")
    |> assert_a11y()
  end

  test "the combobox fixture with closed and open comboboxes in light and dark mode", %{conn: conn} do
    open = fn conn, id ->
      conn
      |> click("##{id}-trigger")
      |> assert_has("##{id}-trigger[aria-expanded=true]")
    end

    conn
    |> visit(~p"/admin/combobox")
    |> assert_has("body .phx-connected")
    |> open.("combobox_tags")
    |> click("#combobox_tags-listbox [data-part=option][data-value=Elixir]")
    |> assert_has("#combobox_tags-value [data-part=badge]")
    |> click("h1")
    |> assert_a11y()
    |> evaluate("document.documentElement.dataset.theme = 'dark'")
    |> assert_a11y()
    |> evaluate("document.documentElement.dataset.theme = 'light'")
    # Grouped options with a disabled one, and an active option.
    |> open.("combobox_fruit")
    |> press("#combobox_fruit-popup [data-part=search]", "ArrowDown")
    |> assert_a11y()
    |> evaluate("document.documentElement.dataset.theme = 'dark'")
    |> assert_a11y()
    # Badges and options disabled by max.
    |> open.("combobox_tags")
    |> click("#combobox_tags-listbox [data-part=option][data-value=Phoenix]")
    |> click("#combobox_tags-listbox [data-part=option][data-value=Ecto]")
    |> assert_has("#combobox_tags-listbox [data-part=option][aria-disabled=true]", count: 4)
    |> assert_a11y()
    |> evaluate("document.documentElement.dataset.theme = 'light'")
    |> assert_a11y()
    # The select all line with an enabled and a disabled button.
    |> open.("combobox_all_tags")
    |> assert_has("#combobox_all_tags [data-part=deselect-all-button][aria-disabled=true]")
    |> assert_a11y()
    |> evaluate("document.documentElement.dataset.theme = 'dark'")
    |> assert_a11y()
  end

  test "pagination with a placeholder for skipped pages", %{conn: conn} do
    insert_list(100, :film_review)

    conn
    |> visit(~p"/admin/film-reviews")
    |> assert_has(".join-item", text: "...")
    |> assert_a11y()
  end

  test "an open multi select of a resource action with a selection", %{conn: conn} do
    conn
    |> visit(~p"/admin/users/invite/resource-action")
    |> assert_has("body .phx-connected")
    |> press("#resource-form_users-trigger", "Enter")
    |> assert_has("#resource-form_users-listbox [role=option]", count: 2)
    |> click("#resource-form_users-listbox [role=option]:first-child")
    |> assert_has("#resource-form_users [data-part=badge]", count: 1)
    |> assert_a11y()
  end
end
