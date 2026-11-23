defmodule Backpex.E2E.A11yTest do
  use Backpex.E2ECase, async: true

  alias Playwright.Page

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
      |> assert_a11y()
    end
  end

  test "the delete confirmation modal", %{conn: conn} do
    address = insert(:address)

    conn
    |> visit(~p"/admin/addresses")
    |> unwrap(&Page.click!(&1, "#item-action-delete-#{address.id}"))
    |> assert_has("#action-confirm-modal[open]")
    |> assert_a11y()
  end

  test "the filter dropdown with an open multi select", %{conn: conn} do
    insert_list(3, :post)

    conn
    |> visit(~p"/admin/posts")
    |> unwrap(&Page.press!(&1, "#filter-dropdown-trigger", "Enter"))
    |> unwrap(&Page.press!(&1, "#filter-dropdown-menu [id^=multi-select-][id$=-trigger]", "Enter"))
    |> assert_has("#filter-dropdown-menu input[name='filters[user_id][]']:visible", count: 3)
    |> assert_a11y()
  end

  test "an open has many dropdown in light and dark mode", %{conn: conn} do
    insert_list(3, :tag)

    conn
    |> visit(~p"/admin/posts/new")
    |> unwrap(&Page.press!(&1, "#has-many-dropdown-tags-trigger", "Enter"))
    |> assert_has("#has-many-dropdown-tags-menu input[name='change[tags][]']:visible", count: 3)
    |> assert_a11y()
    |> unwrap(&Page.evaluate!(&1, "document.documentElement.dataset.theme = 'dark'"))
    |> assert_a11y()
  end

  test "pagination with a placeholder for skipped pages", %{conn: conn} do
    insert_list(100, :film_review)

    conn
    |> visit(~p"/admin/film-reviews")
    |> assert_has(".join-item", text: "...")
    |> assert_a11y()
  end

  test "an open multi select of a resource action", %{conn: conn} do
    conn
    |> visit(~p"/admin/users/invite/resource-action")
    |> unwrap(&Page.press!(&1, "[id^=multi-select-][id$=-trigger]", "Enter"))
    |> assert_has("input[name='change[users][]']:visible", count: 2)
    |> assert_a11y()
  end
end
