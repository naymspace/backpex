defmodule DemoWeb.Live.Address.NewLiveTest do
  use DemoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  describe "addresses live resource new" do
    test "is rendered", %{conn: conn} do
      conn
      |> visit(~p"/admin/addresses/new")
      |> assert_has("h1", text: "New Address", exact: true)
      |> assert_has("button", text: "Cancel", exact: true)
      |> assert_has("button", text: "Save", exact: true)
    end

    test "submit form", %{conn: conn} do
      conn
      |> visit(~p"/admin/addresses/new")
      |> unwrap(fn view ->
        view
        |> form("#resource-form",
          change: %{street: "Main Street", zip: "10115", city: "Berlin", country: "de"}
        )
        |> put_submitter("button[value=save]")
        |> render_submit()
      end)
      |> assert_has("table tbody tr", count: 1)
      |> assert_has("p", text: "Main Street", exact: true)
      |> assert_has("p", text: "Berlin", exact: true)
    end

    test "multiple validation errors displayed", %{conn: conn} do
      conn
      |> visit(~p"/admin/addresses/new")
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
