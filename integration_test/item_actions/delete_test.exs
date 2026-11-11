defmodule Backpex.Integration.ItemActions.DeleteTest do
  use Backpex.ConnCase, async: true

  alias Backpex.Test.Address
  alias Backpex.Test.Category
  alias Backpex.Test.Repo
  alias Backpex.Test.UsersAddresses

  setup do
    %{category: insert(:category, name: "Elixir")}
  end

  test "deletes the item from the index view", %{conn: conn} do
    conn
    |> visit(~p"/admin/categories")
    |> assert_has("td", text: "Elixir", exact: true)
    # The toolbar has a "Delete" button for the selected items, too.
    |> within("table", &click_button(&1, "Delete"))
    |> confirm()
    |> assert_path(~p"/admin/categories")
    |> refute_has("td", text: "Elixir", exact: true)
    |> assert_has("div", text: "Category has been deleted successfully.", exact: true)
  end

  test "deletes the item from the show view", %{conn: conn, category: category} do
    conn
    |> visit(~p"/admin/categories/#{category.id}/show")
    |> assert_has("dd", text: "Elixir", exact: true)
    |> click_button("Delete")
    |> confirm()
    |> assert_path(~p"/admin/categories")
    |> refute_has("td", text: "Elixir", exact: true)
    |> assert_has("div", text: "Category has been deleted successfully.", exact: true)
  end

  test "does not delete an item when on_item_deleting/2 refuses it", %{conn: conn, category: category} do
    insert(:post, category: category)

    conn
    |> visit(~p"/admin/categories")
    |> within("table", &click_button(&1, "Delete"))
    |> confirm()
    |> assert_has("div", text: "Elixir can't be deleted, because posts belong to it.", exact: true)
    |> assert_has("td", text: "Elixir", exact: true)

    assert Repo.get(Category, category.id)
  end

  test "stays on the show view when on_item_deleting/2 refuses the item", %{conn: conn, category: category} do
    insert(:post, category: category)

    conn
    |> visit(~p"/admin/categories/#{category.id}/show")
    |> click_button("Delete")
    |> confirm()
    |> assert_path(~p"/admin/categories/#{category.id}/show")
    |> assert_has("div", text: "Elixir can't be deleted, because posts belong to it.", exact: true)
    |> assert_has("dd", text: "Elixir", exact: true)

    assert Repo.get(Category, category.id)
  end

  describe "an item that other records reference" do
    setup do
      addresses = insert_pair(:address)
      insert(:user, users_addresses: Enum.map(addresses, &%UsersAddresses{address: &1, type: :billing}))

      %{addresses: addresses}
    end

    test "is not deleted and the error says so", %{conn: conn, addresses: [address | _addresses]} do
      conn
      |> visit(~p"/admin/addresses/#{address.id}/show")
      |> click_button("Delete")
      |> confirm()
      |> assert_has("div",
        text: "An error occurred while deleting the Address! The item is used elsewhere.",
        exact: true
      )

      assert Repo.get(Address, address.id)
    end

    test "is not deleted with the other selected items", %{conn: conn, addresses: addresses} do
      addresses
      |> Enum.reduce(visit(conn, ~p"/admin/addresses"), fn address, session ->
        check(session, "#select-input-#{address.id}", "Select item with id: #{address.id}")
      end)
      |> click_button("button.btn-outline", "Delete")
      |> confirm()
      |> assert_has("div",
        text: "An error occurred while deleting 2 Addresses! The items are used elsewhere.",
        exact: true
      )

      assert Repo.aggregate(Address, :count) == 2
    end
  end

  defp confirm(session) do
    within(session, "#resource-form", &click_button(&1, "Delete"))
  end
end
