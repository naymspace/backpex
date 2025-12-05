defmodule DemoWeb.Live.Product.ShowLiveTest do
  use DemoWeb.ConnCase, async: false

  import Demo.EctoFactory

  describe "products live resource show" do
    test "is rendered", %{conn: conn} do
      product =
        insert(:product, %{
          name: "Test Product",
          quantity: 100,
          manufacturer: "https://example.com",
          price: Money.new(1500, :USD)
        })

      conn
      |> visit(~p"/admin/products/#{product.id}/show")
      |> assert_has("h1", text: "Product", exact: true)
      |> assert_has("dt", text: "Name", exact: true)
      |> assert_has("dd", text: "Test Product", exact: true)
      |> assert_has("dt", text: "Quantity", exact: true)
      |> assert_has("dd", text: "100", exact: true)
    end
  end
end
