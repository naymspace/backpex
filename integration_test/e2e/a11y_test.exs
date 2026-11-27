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
    test "#{path} #{view}", %{session: session} = context do
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

      session
      |> visit(path)
      |> assert_a11y()
    end
  end

  test "the delete confirmation modal", %{session: session} do
    address = insert(:address)

    session
    |> visit(~p"/admin/addresses")
    |> click(by_css("#item-action-delete-#{address.id}"))
    |> assert_has(by_css("#action-confirm-modal[open]"))
    |> assert_a11y()
  end

  test "the filter dropdown with an open multi select", %{session: session} do
    insert_list(3, :post)
    user_options = by_css("#filter-dropdown-menu input[name='filters[user_id][]']") |> filter(visible: true)

    session
    |> visit(~p"/admin/posts")
    |> press(by_css("#filter-dropdown-trigger"), "Enter")
    |> press(by_css("#filter-dropdown-menu [id^=multi-select-][id$=-trigger]"), "Enter")
    |> assert(count(user_options, 3))
    |> assert_a11y()
  end

  test "an open has many dropdown in light and dark mode", %{session: session} do
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

  test "pagination with a placeholder for skipped pages", %{session: session} do
    insert_list(100, :film_review)

    session
    |> visit(~p"/admin/film-reviews")
    |> assert_has(by_css(".join-item") |> filter(has_text: "..."))
    |> assert_a11y()
  end

  test "an open multi select of a resource action", %{session: session} do
    user_options = by_css("input[name='change[users][]']") |> filter(visible: true)

    session
    |> visit(~p"/admin/users/invite/resource-action")
    |> press(by_css("[id^=multi-select-][id$=-trigger]"), "Enter")
    |> assert(count(user_options, 2))
    |> assert_a11y()
  end
end
