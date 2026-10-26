defmodule DemoWeb.Live.Category.DeleteItemActionLiveTest do
  use DemoWeb.ConnCase, async: false

  import Demo.EctoFactory
  import Demo.Support.LiveResourceTests
  import Phoenix.LiveViewTest

  describe "delete item action on index view" do
    test "deletes item successfully", %{conn: conn} do
      category = insert(:category)

      test_delete_from_index(
        conn,
        ~p"/admin/categories",
        category,
        :name,
        category.name,
        "Category has been deleted successfully."
      )
    end

    test "does not delete a category that posts belong to", %{conn: conn} do
      category = insert(:category)
      insert(:post, category: category)

      conn
      |> visit(~p"/admin/categories")
      |> unwrap(fn view ->
        view
        |> element("button[aria-label='Delete'][phx-value-item-id='#{category.id}']")
        |> render_click()
      end)
      |> unwrap(fn view ->
        view
        |> form("#resource-form")
        |> render_submit()
      end)
      |> assert_has("div", text: "#{category.name} can't be deleted, because posts belong to it.", exact: true)
      |> assert_has("td", text: category.name, exact: true)

      assert Demo.Repo.get(Demo.Category, category.id)
    end
  end

  describe "delete item action on show view" do
    test "deletes item successfully", %{conn: conn} do
      category = insert(:category)

      test_delete_from_show(
        conn,
        ~p"/admin/categories",
        category,
        :name,
        category.name,
        "Category has been deleted successfully."
      )
    end
  end
end
