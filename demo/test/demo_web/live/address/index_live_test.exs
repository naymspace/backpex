defmodule DemoWeb.Live.Address.IndexLiveTest do
  use DemoWeb.ConnCase, async: false

  import Demo.EctoFactory
  import Demo.Support.LiveResourceTests
  import Phoenix.LiveViewTest

  describe "addresses live resource index" do
    test "is rendered", %{conn: conn} do
      insert_list(3, :address)

      conn
      |> visit(~p"/admin/addresses")
      |> assert_has("h1", text: "Addresses", exact: true)
      |> assert_has("button", text: "New Address", exact: true)
      |> assert_has("button[disabled]", text: "Delete", exact: true)
      |> assert_has("div", text: "Items 1 to 3 (3 total)", exact: true)
      |> assert_has("table tbody tr", count: 3)
    end

    test "search for items", %{conn: conn} do
      insert(:address, %{city: "Berlin", street: "Main Street", zip: "10115", country: :de})
      insert(:address, %{city: "Munich", street: "Park Ave", zip: "80331", country: :de})

      conn
      |> visit(~p"/admin/addresses")
      |> assert_has(".table tbody tr", count: 2)
      |> unwrap(fn view ->
        view
        |> form("#index-search-form", index_search: %{value: "Munich"})
        |> render_change()
      end)
      |> assert_has("table tbody tr", count: 1)
      |> refute_has("tr", text: "Berlin")
      |> assert_has("tr", text: "Munich")
    end

    test "basic functionality", %{conn: conn} do
      addresses = insert_list(3, :address)

      test_table_rows_count(conn, ~p"/admin/addresses", Enum.count(addresses))
      test_delete_button_disabled_enabled(conn, ~p"/admin/addresses", addresses)
      test_show_action_redirect(conn, ~p"/admin/addresses", addresses)
      test_edit_action_redirect(conn, ~p"/admin/addresses", addresses)
    end
  end
end
