defmodule Backpex.Integration.Fields.BelongsToTest do
  use Backpex.ConnCase, async: true

  alias Backpex.Test.Product

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
end
