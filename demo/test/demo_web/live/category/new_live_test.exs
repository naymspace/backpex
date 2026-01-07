defmodule DemoWeb.Live.Category.NewLiveTest do
  use DemoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  describe "categories live resource new" do
    test "is rendered", %{conn: conn} do
      conn
      |> visit(~p"/admin/categories/new")
      |> assert_has("h1", text: "New Category", exact: true)
      |> assert_has("button", text: "Cancel", exact: true)
      |> assert_has("button", text: "Save", exact: true)
    end

    test "submit form", %{conn: conn} do
      conn
      |> visit(~p"/admin/categories/new")
      |> unwrap(fn view ->
        view
        |> form("#resource-form", change: %{name: "New"})
        |> put_submitter("button[value=save]")
        |> render_submit()
      end)
      |> assert_has("table tbody tr", count: 1)
      |> assert_has("p", text: "New", exact: true)
    end

    test "required field shows error when empty", %{conn: conn} do
      conn
      |> visit(~p"/admin/categories/new")
      |> unwrap(fn view ->
        view
        |> form("#resource-form", change: %{name: ""})
        |> render_change()
      end)
      |> assert_has("form#resource-form")
    end

    test "submission with empty required field shows error", %{conn: conn} do
      conn
      |> visit(~p"/admin/categories/new")
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
