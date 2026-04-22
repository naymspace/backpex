defmodule DemoWeb.Live.Product.IndexLiveTest do
  use DemoWeb.ConnCase, async: false

  import Demo.EctoFactory
  import Phoenix.LiveViewTest
  import Demo.Support.LiveResourceTests

  describe "products live resource index" do
    test "is rendered", %{conn: conn} do
      insert_list(3, :product)

      conn
      |> visit(~p"/admin/products")
      |> assert_has("h1", text: "Products", exact: true)
      |> assert_has("button", text: "New Product", exact: true)
      |> assert_has("button[disabled]", text: "Delete", exact: true)
      |> assert_has("div", text: "Items 1 to 3 (3 total)", exact: true)
      |> assert_has("table tbody tr", count: 3)
    end

    test "search for items", %{conn: conn} do
      insert(:product, %{
        name: "Widget",
        quantity: 100,
        manufacturer: "https://example.com",
        price: Money.new(1000, :USD)
      })

      insert(:product, %{
        name: "Gadget",
        quantity: 200,
        manufacturer: "https://example.com",
        price: Money.new(2000, :USD)
      })

      conn
      |> visit(~p"/admin/products")
      |> assert_has(".table tbody tr", count: 2)
      |> unwrap(fn view ->
        view
        |> form("#index-search-form", index_search: %{value: "Gadget"})
        |> render_change()
      end)
      |> assert_has("table tbody tr", count: 1)
      |> refute_has("tr", text: "Widget")
      |> assert_has("tr", text: "Gadget")
    end

    test "basic functionality", %{conn: conn} do
      products = insert_list(3, :product)

      test_table_rows_count(conn, ~p"/admin/products", Enum.count(products))
      test_delete_button_disabled_enabled(conn, ~p"/admin/products", products)
      test_show_action_redirect(conn, ~p"/admin/products", products)
      test_edit_action_redirect(conn, ~p"/admin/products", products)
    end
  end
end
