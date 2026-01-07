defmodule DemoWeb.Live.Tag.NewLiveTest do
  use DemoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  describe "tags live resource new" do
    test "is rendered", %{conn: conn} do
      conn
      |> visit(~p"/admin/tags/new")
      |> assert_has("h1", text: "New Tag", exact: true)
      |> assert_has("button", text: "Cancel", exact: true)
      |> assert_has("button", text: "Save", exact: true)
    end

    test "submit form", %{conn: conn} do
      conn
      |> visit(~p"/admin/tags/new")
      |> unwrap(fn view ->
        view
        |> form("#resource-form", change: %{name: "Phoenix"})
        |> put_submitter("button[value=save]")
        |> render_submit()
      end)
      |> assert_has("table tbody tr", count: 1)
      |> assert_has("p", text: "Phoenix", exact: true)
    end
  end
end
