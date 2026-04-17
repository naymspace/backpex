defmodule DemoWeb.Live.Address.EditLiveTest do
  use DemoWeb.ConnCase, async: false

  import Demo.EctoFactory
  import Phoenix.LiveViewTest

  describe "addresses live resource edit" do
    test "is rendered", %{conn: conn} do
      address = insert(:address)

      conn
      |> visit(~p"/admin/addresses/#{address.id}/edit")
      |> assert_has("h1", text: "Edit Address", exact: true)
      |> assert_has("button", text: "Cancel", exact: true)
      |> assert_has("button", text: "Save", exact: true)
    end

    test "submit form", %{conn: conn} do
      address = insert(:address, %{street: "Old Street", zip: "12345", city: "Old City", country: :de})

      conn
      |> visit(~p"/admin/addresses/#{address.id}/edit")
      |> unwrap(fn view ->
        view
        |> form("#resource-form",
          change: %{street: "New Street", zip: "54321", city: "New City", country: "at"}
        )
        |> put_submitter("button[value=save]")
        |> render_submit()
      end)
      |> assert_has("table tbody tr", count: 1)
      |> assert_has("p", text: "New Street", exact: true)
      |> assert_has("p", text: "New City", exact: true)
    end

    test "editing with invalid data shows errors", %{conn: conn} do
      address = insert(:address, %{street: "Main Street", zip: "12345", city: "Berlin", country: :de})

      conn
      |> visit(~p"/admin/addresses/#{address.id}/edit")
      |> unwrap(fn view ->
        view
        |> form("#resource-form", change: %{street: "", zip: "", city: ""})
        |> put_submitter("button[value=save]")
        |> render_submit()
      end)
      |> assert_has("form#resource-form")
      |> assert_has("p", text: "can't be blank", count: 3)
    end
  end
end
