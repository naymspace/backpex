defmodule DemoWeb.Live.User.ShowLiveTest do
  use DemoWeb.ConnCase, async: false

  import Demo.EctoFactory

  describe "users live resource show" do
    test "renders the addresses with their pivot fields", %{conn: conn} do
      user = insert(:user, users_addresses: [%Demo.UsersAddresses{address: build(:address), type: :billing}])

      conn
      |> visit(~p"/admin/users/#{user.id}/show")
      |> assert_has("h1", text: "User", exact: true)
      |> assert_has("td", text: "Billing")
    end
  end
end
