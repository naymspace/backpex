defmodule DemoWeb.Live.Category.DeleteItemActionLiveTest do
  use DemoWeb.ConnCase, async: false

  import Demo.EctoFactory
  import Phoenix.LiveViewTest
  import Demo.Support.LiveResourceTests

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
