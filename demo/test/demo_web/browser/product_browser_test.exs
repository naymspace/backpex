defmodule DemoWeb.Browser.ProductBrowserTest do
  use PhoenixTest.Playwright.Case, async: false
  use DemoWeb, :verified_routes
  use DemoWeb.A11yAssertions

  import Demo.EctoFactory

  @moduletag :playwright

  describe "products index" do
    test "a11y", %{conn: conn} do
      insert_list(10, :product)

      conn
      |> visit(~p"/admin/products")
      |> assert_a11y()
    end
  end

  describe "products show" do
    test "a11y", %{conn: conn} do
      product = insert(:product)

      conn
      |> visit(~p"/admin/products/#{product.id}/show")
      |> assert_a11y()
    end
  end

  describe "products edit" do
    test "a11y", %{conn: conn} do
      product = insert(:product)

      conn
      |> visit(~p"/admin/products/#{product.id}/edit")
      |> assert_a11y()
    end
  end

  describe "products new" do
    test "a11y", %{conn: conn} do
      conn
      |> visit(~p"/admin/products/new")
      |> assert_a11y()
    end
  end
end
