defmodule DemoWeb.Live.SmokeTest do
  @moduledoc """
  Renders every view of every LiveResource of the demo. The behaviour of Backpex is tested in the library, these tests
  only make sure the demo configuration works.
  """
  use DemoWeb.ConnCase, async: false

  import Demo.EctoFactory

  # `{path, factory, primary key, singular name, plural name, views}`
  @resources [
    {"/admin/users", :user, :id, "User", "Users", [:index, :new, :show, :edit]},
    {"/admin/addresses", :address, :id, "Address", "Addresses", [:index, :new, :show, :edit]},
    {"/admin/products", :product, :id, "Product", "Products", [:index, :new, :show, :edit]},
    {"/admin/invoices", :invoice, :id, "Invoice", "Invoices", [:index]},
    {"/admin/posts", :post, :id, "Post", "Posts", [:index, :new, :show, :edit]},
    {"/admin/categories", :category, :id, "Category", "Categories", [:index, :new, :show, :edit]},
    {"/admin/tags", :tag, :id, "Tag", "Tags", [:index, :new, :show, :edit]},
    {"/admin/film-reviews", :film_review, :id, "Film Review", "Film Reviews", [:index, :new, :show, :edit]},
    {"/admin/short-links", :short_link, :short_key, "Short Link", "Short Links", [:index, :new, :show, :edit]}
  ]

  for {path, factory, primary_key, singular, plural, views} <- @resources, view <- views do
    @tag path: path, factory: factory, primary_key: primary_key, singular: singular, plural: plural, view: view
    test "#{path} #{view} is rendered", %{conn: conn} = context do
      item = insert(context.factory)
      id = item |> Map.fetch!(context.primary_key) |> to_string() |> URI.encode_www_form()

      {path, heading} =
        case context.view do
          :index -> {context.path, context.plural}
          :new -> {"#{context.path}/new", "New #{context.singular}"}
          :show -> {"#{context.path}/#{id}/show", context.singular}
          :edit -> {"#{context.path}/#{id}/edit", "Edit #{context.singular}"}
        end

      conn
      |> visit(path)
      |> assert_has("h1", text: heading, exact: true)
    end
  end
end
