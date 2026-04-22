defmodule DemoWeb.Live.Category.EditItemActionLiveTest do
  use DemoWeb.ConnCase, async: false

  import Demo.EctoFactory
  import Phoenix.LiveViewTest
  import Demo.Support.LiveResourceTests

  describe "edit item action on index view" do
    test "redirects to index view", %{conn: conn} do
      category = insert(:category, name: "Tech")

      test_edit_from_index_save(
        conn,
        ~p"/admin/categories",
        category,
        :name,
        "Tech",
        "Updated Tech"
      )
    end

    test "redirects to index view on cancel", %{conn: conn} do
      category = insert(:category, name: "Tech")

      test_edit_from_index_cancel(
        conn,
        ~p"/admin/categories",
        category,
        :name,
        "Tech"
      )
    end
  end

  describe "edit item action on show view" do
    test "redirects to show view", %{conn: conn} do
      category = insert(:category, name: "Tech")

      test_edit_from_show_save(
        conn,
        ~p"/admin/categories",
        category,
        :name,
        "Tech",
        "Updated Tech"
      )
    end

    test "redirects to show view on cancel", %{conn: conn} do
      category = insert(:category, name: "Tech")

      test_edit_from_show_cancel(
        conn,
        ~p"/admin/categories",
        category,
        :name,
        "Tech"
      )
    end
  end
end
