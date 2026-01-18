defmodule DemoWeb.Live.Category.EditLiveTest do
  use DemoWeb.ConnCase, async: false

  import Demo.EctoFactory
  import Phoenix.LiveViewTest

  describe "categories live resource edit" do
    test "is rendered", %{conn: conn} do
      category = insert(:category)

      conn
      |> visit(~p"/admin/categories/#{category.id}/edit")
      |> assert_has("h1", text: "Edit Category", exact: true)
      |> assert_has("button", text: "Cancel", exact: true)
      |> assert_has("button", text: "Save", exact: true)
    end

    test "submit form", %{conn: conn} do
      category = insert(:category, %{name: "Tech"})

      conn
      |> visit(~p"/admin/categories/#{category.id}/edit")
      |> unwrap(fn view ->
        view
        |> form("#resource-form", change: %{name: "New"})
        |> put_submitter("button[value=save]")
        |> render_submit()
      end)
      |> assert_has("table tbody tr", count: 1)
      |> assert_has("p", text: "New", exact: true)
    end

    test "editing with invalid data shows error", %{conn: conn} do
      category = insert(:category, %{name: "Original Name"})

      conn
      |> visit(~p"/admin/categories/#{category.id}/edit")
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
