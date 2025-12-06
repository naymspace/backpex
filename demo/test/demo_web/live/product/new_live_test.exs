defmodule DemoWeb.Live.Product.NewLiveTest do
  use DemoWeb.ConnCase, async: false

  describe "products live resource new" do
    test "is rendered", %{conn: conn} do
      conn
      |> visit(~p"/admin/products/new")
      |> assert_has("h1", text: "New Product", exact: true)
      |> assert_has("button", text: "Cancel", exact: true)
      |> assert_has("button", text: "Save", exact: true)
    end
  end
end
