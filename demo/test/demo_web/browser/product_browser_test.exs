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

    test "removes inline rows with the keyboard", %{conn: conn} do
      short_links = [
        build(:short_link, url: "https://example.com/first"),
        build(:short_link, url: "https://example.com/second")
      ]

      product = insert(:product, suppliers: [], short_links: short_links)
      url_input = fn index -> "input[type=text][name='change[short_links][#{index}][url]']" end

      conn
      |> visit(~p"/admin/products/#{product.id}/edit")
      |> assert_has("body .phx-connected")
      |> press(url_input.(0), "Tab")
      |> evaluate("document.activeElement.getAttribute('aria-label')", &assert(&1 == "Delete entry 1"))
      |> press("button[aria-label='Delete entry 1']", "Enter")
      |> refute_has(url_input.(1))
      |> assert_has(url_input.(0), value: "https://example.com/second")
      |> evaluate("document.activeElement.getAttribute('aria-label')", &assert(&1 == "Delete entry 1"))
      |> press("button[aria-label='Delete entry 1']", "Space")
      |> refute_has(url_input.(0))
      |> evaluate("document.activeElement.getAttribute('aria-label')", &assert(&1 == "Add entry"))
      |> assert_a11y()
      |> click_button("Save")
      |> assert_path(~p"/admin/products")

      assert %{short_links: []} = Demo.Product |> Demo.Repo.get!(product.id) |> Demo.Repo.preload(:short_links)
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
