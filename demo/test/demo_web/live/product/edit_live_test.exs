defmodule DemoWeb.Live.Product.EditLiveTest do
  use DemoWeb.ConnCase, async: false

  import Demo.EctoFactory
  import Phoenix.LiveViewTest

  describe "products live resource edit" do
    test "is rendered", %{conn: conn} do
      product = insert(:product)

      conn
      |> visit(~p"/admin/products/#{product.id}/edit")
      |> assert_has("h1", text: "Edit Product", exact: true)
      |> assert_has("button", text: "Cancel", exact: true)
      |> assert_has("button", text: "Save", exact: true)
    end

    test "submit form", %{conn: conn} do
      product =
        insert(:product, %{
          name: "Old Widget",
          quantity: 50,
          manufacturer: "https://example.com",
          price: Money.new(1000, :USD)
        })

      conn
      |> visit(~p"/admin/products/#{product.id}/edit")
      |> unwrap(fn view ->
        view
        |> form("#resource-form",
          change: %{name: "New Widget", quantity: "100"}
        )
        |> put_submitter("button[value=save]")
        |> render_submit()
      end)
      |> assert_has("table tbody tr", count: 1)
      |> assert_has("p", text: "New Widget", exact: true)
    end

    test "editing with invalid data shows error", %{conn: conn} do
      product =
        insert(:product, %{
          name: "Widget",
          quantity: 50,
          manufacturer: "https://example.com",
          price: Money.new(1000, :USD)
        })

      conn
      |> visit(~p"/admin/products/#{product.id}/edit")
      |> unwrap(fn view ->
        view
        |> form("#resource-form", change: %{name: ""})
        |> put_submitter("button[value=save]")
        |> render_submit()
      end)
      |> assert_has("form#resource-form")
      |> assert_has("p", text: "can't be blank")
    end
  end
end
