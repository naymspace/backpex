defmodule Backpex.Integration.Fields.BelongsToTest do
  use Backpex.ConnCase, async: true

  import Phoenix.LiveViewTest, only: [form: 2, put_submitter: 2, render_submit: 2]

  alias Backpex.Test.Post
  alias Backpex.Test.Product

  # The author of a post is a BelongsTo field with an `options_query` that excludes deleted users.
  describe "options_query" do
    test "refuses to save an author that is not an option", %{conn: conn} do
      post = insert(:post)
      deleted_user = insert(:user, deleted_at: DateTime.utc_now(:second))

      conn
      |> visit(~p"/admin/posts/#{post.id}/edit")
      |> save(%{user_id: deleted_user.id})
      |> assert_has("div.fieldset:has(select[name='change[user_id]']) > p.text-error", text: "is invalid", exact: true)

      assert Repo.get!(Post, post.id).user_id == post.user_id
    end

    test "refuses to create an item with an author that is not an option", %{conn: conn} do
      deleted_user = insert(:user, deleted_at: DateTime.utc_now(:second))

      conn
      |> visit(~p"/admin/posts/new")
      |> save(%{title: "Title", body: "Body", user_id: deleted_user.id})

      refute Repo.get_by(Post, title: "Title")
    end

    test "saves an author that is an option", %{conn: conn} do
      post = insert(:post)
      other_user = insert(:user)

      conn
      |> visit(~p"/admin/posts/#{post.id}/edit")
      |> save(%{user_id: other_user.id})

      assert Repo.get!(Post, post.id).user_id == other_user.id
    end

    test "keeps the author of the item that is no longer an option", %{conn: conn} do
      deleted_user = insert(:user, deleted_at: DateTime.utc_now(:second))
      post = insert(:post, user: deleted_user)

      conn
      |> visit(~p"/admin/posts/#{post.id}/edit")
      |> save(%{title: "After", user_id: deleted_user.id})

      assert %Post{title: "After", user_id: user_id} = Repo.get!(Post, post.id)
      assert user_id == deleted_user.id
    end
  end

  # `Backpex.Test.ProductShortLinksLive` has a BelongsTo field of `Backpex.Test.ShortLink`, whose key is `short_key`.
  describe "a related schema whose key is not id" do
    setup do
      # The keys come from the factory's sequence: equal keys would make concurrent tests wait for each other.
      link = insert(:short_link, url: "https://docs.example.com/")
      other_link = insert(:short_link, url: "https://blog.example.com/")

      %{product: insert(:product, featured_short_link: link), link: link, other_link: other_link}
    end

    test "renders the keys as option values and selects the current one", context do
      %{conn: conn, product: product, link: link, other_link: other_link} = context

      conn
      |> visit(~p"/admin/product-short-links/#{product.id}/edit")
      |> assert_has("select", label: "Featured Short Link", selected: "https://docs.example.com/")
      |> assert_has("select option[value='#{link.short_key}'][selected]", text: link.url, exact: true)
      |> assert_has("select option[value='#{other_link.short_key}']:not([selected])", text: other_link.url, exact: true)
    end

    test "saves the key of the chosen option", %{conn: conn, product: product, other_link: other_link} do
      conn
      |> visit(~p"/admin/product-short-links/#{product.id}/edit")
      |> select("Featured Short Link", option: other_link.url)
      |> click_button("Save")
      |> assert_path(~p"/admin/product-short-links")

      assert Repo.get!(Product, product.id).featured_short_link_key == other_link.short_key
    end
  end

  # A crafted client can send any value, not only the options of the select.
  defp save(session, params) do
    unwrap(session, fn view ->
      view
      |> form("#resource-form")
      |> put_submitter("button[value=save]")
      |> render_submit(%{change: params})
    end)
  end
end
