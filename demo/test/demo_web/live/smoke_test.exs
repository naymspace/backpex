defmodule DemoWeb.Live.SmokeTest do
  @moduledoc """
  Renders every view of every LiveResource of the demo and runs its own resource actions, item actions and filters. The
  behaviour of Backpex is tested in the library, these tests only make sure the demo configuration works.
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

  describe "resource actions" do
    test "send an email", %{conn: conn} do
      conn
      |> visit(~p"/admin/users/invite/resource-action")
      |> check("Alex")
      |> fill_in("Text", with: "Hello")
      |> within("#resource-form", &click_button(&1, "Send email"))
      |> assert_has("div", text: "An email has been successfully sent to the specified users.")
    end

    test "render the upload form", %{conn: conn} do
      conn
      |> visit(~p"/admin/users/upload/resource-action")
      |> assert_has("#resource-action-modal", text: "Upload file")
      |> assert_has("#resource-form input[type=file]")
    end
  end

  describe "item actions" do
    test "soft delete a user", %{conn: conn} do
      user = insert(:user, username: "soft_deleted")

      conn
      |> visit(~p"/admin/users")
      |> within("#row-item-#{user.id}", &click_button(&1, "Delete"))
      |> fill_in("Reason", with: "Left the company")
      |> within("#resource-form", &click_button(&1, "Delete"))
      |> refute_has("input[value='soft_deleted']")

      assert Demo.Repo.get!(Demo.User, user.id).deleted_at
    end

    test "duplicate a tag", %{conn: conn} do
      tag = insert(:tag, name: "Elixir")

      conn
      |> visit(~p"/admin/tags/#{tag.id}/show")
      |> click_button("Duplicate Elixir")
      |> fill_in("Name", with: "Elixir copy")
      |> within("#resource-form", &click_button(&1, "Duplicate"))
      |> assert_has("dd", text: "Elixir copy")
    end
  end

  describe "filters" do
    setup do
      post = insert(:post, published: true, likes: 50)
      %{post: post}
    end

    test "every filter of the posts applies", %{conn: conn, post: post} do
      yesterday = Date.utc_today() |> Date.add(-1) |> Date.to_iso8601()
      tomorrow = Date.utc_today() |> Date.add(1) |> Date.to_iso8601()

      filters = [
        %{"category_id" => post.category_id},
        %{"user_id" => [post.user_id]},
        %{"likes" => %{"start" => "1", "end" => "100"}},
        %{"inserted_at" => %{"start" => yesterday, "end" => tomorrow}},
        %{"published" => ["published"]}
      ]

      for filter <- filters do
        conn
        |> visit(~p"/admin/posts?#{%{"filters" => filter}}")
        |> assert_has("table tbody tr", text: post.title)
      end
    end

    test "the quantity filter of the products applies", %{conn: conn} do
      insert(:product, name: "Few", quantity: 5)
      insert(:product, name: "Many", quantity: 500)

      conn
      |> visit(~p"/admin/products?#{%{"filters" => %{"quantity" => %{"start" => "1", "end" => "10"}}}}")
      |> assert_has("table tbody tr", text: "Few")
      |> refute_has("table tbody tr", text: "Many")
    end
  end
end
