defmodule DemoWeb.Live.Category.DeleteItemActionLiveTest do
  use DemoWeb.ConnCase, async: false

  import Demo.EctoFactory
  import Phoenix.LiveViewTest

  describe "delete item action on index view" do
    test "deletes item successfully", %{conn: conn} do
      category = insert(:category)

      conn
      |> visit(~p"/admin/categories")
      |> assert_has("td", text: category.name, exact: true)
      |> unwrap(fn view ->
        view
        |> element("button[aria-label='Delete'][phx-value-item-id='#{category.id}']")
        |> render_click()
      end)
      # submit delete action
      |> unwrap(fn view ->
        view
        |> form("#resource-form")
        |> render_submit()
      end)
      |> assert_path(~p"/admin/categories")
      |> refute_has("td", text: category.name, exact: true)
      |> assert_has("div", text: "Category has been deleted successfully.", exact: true)
    end
  end

  describe "delete item action on show view" do
    test "deletes item successfully", %{conn: conn} do
      category = insert(:category)

      conn
      |> visit(~p"/admin/categories/#{category.id}/show")
      |> assert_has("dd", text: category.name, exact: true)
      |> assert_has("#item-action-delete")
      |> unwrap(fn view ->
        view
        |> element("#item-action-delete")
        |> render_click()
      end)
      # submit delete action
      |> unwrap(fn view ->
        view
        |> form("#resource-form")
        |> render_submit()
      end)
      |> assert_path(~p"/admin/categories")
      |> refute_has("td", text: category.name, exact: true)
      |> assert_has("div", text: "Category has been deleted successfully.", exact: true)
    end
  end
end
