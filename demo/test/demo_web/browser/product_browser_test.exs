defmodule DemoWeb.Browser.ProductBrowserTest do
  use DemoWeb.BrowserCase, async: false
  use DemoWeb, :verified_routes
  use DemoWeb.A11yAssertions

  import Demo.EctoFactory

  @moduletag :playwright

  describe "products index" do
    test "a11y", %{session: session} do
      insert_list(10, :product)

      session
      |> visit(~p"/admin/products")
      |> assert_a11y()
    end
  end

  describe "products show" do
    test "a11y", %{session: session} do
      product = insert(:product)

      session
      |> visit(~p"/admin/products/#{product.id}/show")
      |> assert_a11y()
    end
  end

  describe "products edit" do
    test "a11y", %{session: session} do
      product = insert(:product)

      session
      |> visit(~p"/admin/products/#{product.id}/edit")
      |> assert_a11y()
    end
  end

  describe "products new" do
    test "a11y", %{session: session} do
      session
      |> visit(~p"/admin/products/new")
      |> assert_a11y()
    end
  end
end
