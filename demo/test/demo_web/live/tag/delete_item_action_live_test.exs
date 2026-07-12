defmodule DemoWeb.Live.Tag.DeleteItemActionLiveTest do
  use DemoWeb.ConnCase, async: false

  import Demo.EctoFactory
  import Demo.Support.LiveResourceTests
  import Phoenix.LiveViewTest

  describe "delete item action on index view" do
    test "deletes item successfully", %{conn: conn} do
      tag = insert(:tag)

      test_delete_from_index(
        conn,
        ~p"/admin/tags",
        tag,
        :name,
        tag.name
      )
    end
  end

  describe "delete item action on show view" do
    test "deletes item successfully", %{conn: conn} do
      tag = insert(:tag)

      test_delete_from_show(
        conn,
        ~p"/admin/tags",
        tag,
        :name,
        tag.name
      )
    end
  end
end
