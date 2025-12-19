defmodule DemoWeb.Live.Address.ShowLiveTest do
  use DemoWeb.ConnCase, async: false

  import Demo.EctoFactory

  describe "addresses live resource show" do
    test "is rendered", %{conn: conn} do
      address = insert(:address, %{street: "Test Street", zip: "12345", city: "Test City", country: :de})

      conn
      |> visit(~p"/admin/addresses/#{address.id}/show")
      |> assert_has("h1", text: "Address", exact: true)
      |> assert_has("dt", text: "Street Name", exact: true)
      |> assert_has("dd", text: "Test Street", exact: true)
      |> assert_has("dt", text: "Zip Code", exact: true)
      |> assert_has("dd", text: "12345", exact: true)
      |> assert_has("dt", text: "City", exact: true)
      |> assert_has("dd", text: "Test City", exact: true)
      |> assert_has("dt", text: "Country", exact: true)
    end
  end
end
