defmodule DemoWeb.Live.Address.DeleteItemActionLiveTest do
  use DemoWeb.ConnCase, async: false

  import Demo.EctoFactory
  import Demo.Support.LiveResourceTests
  import Phoenix.LiveViewTest

  describe "delete item action on index view" do
    test "deletes item successfully", %{conn: conn} do
      address = insert(:address)

      test_delete_from_index(
        conn,
        ~p"/admin/addresses",
        address,
        :street,
        address.street,
        "Address has been deleted successfully."
      )
    end
  end

  describe "delete item action on show view" do
    test "deletes item successfully", %{conn: conn} do
      address = insert(:address)

      test_delete_from_show(
        conn,
        ~p"/admin/addresses",
        address,
        :street,
        address.street,
        "Address has been deleted successfully."
      )
    end
  end
end
