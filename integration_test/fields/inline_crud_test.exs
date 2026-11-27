defmodule Backpex.Integration.Fields.InlineCRUDTest do
  use Backpex.ConnCase, async: true

  alias Backpex.Test.User.EmergencyContact
  alias Phoenix.LiveViewTest

  require Phoenix.LiveViewTest

  # `Backpex.Test.UserLive` has an InlineCRUD field of the `embeds_one` `emergency_contact`.
  describe "an embeds_one" do
    test "saves an entry for an item without one and then updates that entry", %{conn: conn} do
      user = insert(:user)

      save_emergency_contact(conn, user, %{name: "Ada", phone: "0123"})

      assert %{emergency_contact: %EmergencyContact{id: id, name: "Ada", phone: "0123"}} = Repo.reload!(user)

      save_emergency_contact(conn, user, %{name: "Grace"})

      assert %{emergency_contact: %EmergencyContact{id: ^id, name: "Grace", phone: "0123"}} = Repo.reload!(user)
    end

    test "shows the entry", %{conn: conn} do
      user = insert(:user, emergency_contact: %EmergencyContact{name: "Ada", phone: "0123"})

      conn
      |> visit(~p"/admin/users/#{user.id}/show")
      |> assert_has("th", text: "Phone")
      |> assert_has("td", text: "Ada")
      |> assert_has("td", text: "0123")
    end

    test "shows no row for an item without an entry", %{conn: conn} do
      user = insert(:user)

      conn
      |> visit(~p"/admin/users/#{user.id}/show")
      |> assert_has("th", text: "Phone")
      |> refute_has("td", text: "0123")
    end
  end

  defp save_emergency_contact(conn, user, params) do
    conn
    |> visit(~p"/admin/users/#{user.id}/edit")
    |> unwrap(fn view ->
      view
      |> LiveViewTest.form("#resource-form", change: %{emergency_contact: params})
      |> LiveViewTest.put_submitter("button[value=save]")
      |> LiveViewTest.render_submit()
    end)
  end
end
