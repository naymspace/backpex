defmodule DemoWeb.Live.Address.EditItemActionLiveTest do
  use DemoWeb.ConnCase, async: false

  import Demo.EctoFactory
  import Phoenix.LiveViewTest
  import Demo.Support.LiveResourceTests

  describe "edit item action on index view" do
    test "redirects to index view", %{conn: conn} do
      address = insert(:address, street: "Old Street", zip: "12345", city: "Old City", country: :de)

      test_edit_from_index_save(
        conn,
        ~p"/admin/addresses",
        address,
        :street,
        "Old Street",
        "New Street"
      )
    end

    test "redirects to index view on cancel", %{conn: conn} do
      address = insert(:address, street: "Test Street", zip: "12345", city: "Test City", country: :de)

      test_edit_from_index_cancel(
        conn,
        ~p"/admin/addresses",
        address,
        :street,
        "Test Street"
      )
    end
  end

  describe "edit item action on show view" do
    test "redirects to show view", %{conn: conn} do
      address = insert(:address, street: "Old Street", zip: "12345", city: "Old City", country: :de)

      test_edit_from_show_save(
        conn,
        ~p"/admin/addresses",
        address,
        :street,
        "Old Street",
        "New Street"
      )
    end

    test "redirects to show view on cancel", %{conn: conn} do
      address = insert(:address, street: "Test Street", zip: "12345", city: "Test City", country: :de)

      test_edit_from_show_cancel(
        conn,
        ~p"/admin/addresses",
        address,
        :street,
        "Test Street"
      )
    end
  end
end
