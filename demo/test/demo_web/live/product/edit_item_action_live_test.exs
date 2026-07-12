defmodule DemoWeb.Live.Product.EditItemActionLiveTest do
  use DemoWeb.ConnCase, async: false

  import Demo.EctoFactory
  import Demo.Support.LiveResourceTests
  import Phoenix.LiveViewTest

  describe "edit item action on index view" do
    test "redirects to index view", %{conn: conn} do
      product =
        insert(:product,
          name: "Widget",
          quantity: 100,
          manufacturer: "https://example.com",
          price: Money.new(1000, :USD)
        )

      test_edit_from_index_save(
        conn,
        ~p"/admin/products",
        product,
        :name,
        "Widget",
        "New Widget"
      )
    end

    test "redirects to index view on cancel", %{conn: conn} do
      product =
        insert(:product,
          name: "Widget",
          quantity: 100,
          manufacturer: "https://example.com",
          price: Money.new(1000, :USD)
        )

      test_edit_from_index_cancel(
        conn,
        ~p"/admin/products",
        product,
        :name,
        "Widget"
      )
    end
  end

  describe "edit item action on show view" do
    test "redirects to show view", %{conn: conn} do
      product =
        insert(:product,
          name: "Widget",
          quantity: 100,
          manufacturer: "https://example.com",
          price: Money.new(1000, :USD)
        )

      test_edit_from_show_save(
        conn,
        ~p"/admin/products",
        product,
        :name,
        "Widget",
        "New Widget"
      )
    end

    test "redirects to show view on cancel", %{conn: conn} do
      product =
        insert(:product,
          name: "Widget",
          quantity: 100,
          manufacturer: "https://example.com",
          price: Money.new(1000, :USD)
        )

      test_edit_from_show_cancel(
        conn,
        ~p"/admin/products",
        product,
        :name,
        "Widget"
      )
    end
  end
end
