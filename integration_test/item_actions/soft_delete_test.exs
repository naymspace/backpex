defmodule Backpex.Integration.ItemActions.SoftDeleteTest do
  use Backpex.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Backpex.Test.User

  describe "on the index view" do
    test "asks for the fields of the action", %{conn: conn} do
      user = insert(:user)

      conn
      |> visit(~p"/admin/users")
      |> click_delete(user)
      |> assert_has("label", text: "Reason")
      |> assert_has("textarea[name='change[reason]']")
    end

    test "soft deletes the item with the submitted fields", %{conn: conn} do
      user = insert(:user, username: "usertoremove")

      conn
      |> visit(~p"/admin/users")
      # The username field is index_editable, so it renders as an input.
      |> assert_has("input[value='usertoremove']")
      |> click_delete(user)
      |> submit_reason("User requested deletion")
      |> assert_path(~p"/admin/users")
      |> refute_has("input[value='usertoremove']")
      |> assert_has("div", text: "has been deleted successfully")

      assert %User{deleted_at: %DateTime{}} = Repo.get!(User, user.id)
    end
  end

  describe "on the show view" do
    test "soft deletes the item and returns to the index view", %{conn: conn} do
      user = insert(:user, username: "showuser")

      conn
      |> visit(~p"/admin/users/#{user.id}/show")
      |> assert_has("dd", text: "showuser")
      |> click_show_action()
      |> submit_reason("Deleting from show view")
      |> assert_path(~p"/admin/users")
      |> refute_has("td", text: "showuser")
    end

    test "is not offered when can?/3 denies it", %{conn: conn} do
      admin = insert(:user, role: :admin)

      conn
      |> visit(~p"/admin/users/#{admin.id}/show")
      |> refute_has("#item-action-user_soft_delete")
    end
  end

  describe "return_to param on the show view" do
    test "leads to a local path", %{conn: conn} do
      user = insert(:user)

      conn
      |> visit(~p"/admin/users/#{user.id}/show?return_to=/admin/products")
      |> click_show_action()
      |> submit_reason("Returning to products")
      |> assert_path(~p"/admin/products")
    end

    test "is ignored for an external URL", %{conn: conn} do
      user = insert(:user)

      conn
      |> visit(~p"/admin/users/#{user.id}/show?return_to=https://evil.com")
      |> click_show_action()
      |> submit_reason("Rejecting external redirect")
      |> assert_path(~p"/admin/users")
    end

    test "is ignored for a protocol-relative URL", %{conn: conn} do
      user = insert(:user)

      conn
      |> visit(~p"/admin/users/#{user.id}/show?return_to=//evil.com")
      |> click_show_action()
      |> submit_reason("Rejecting protocol-relative redirect")
      |> assert_path(~p"/admin/users")
    end
  end

  defp click_delete(session, user) do
    unwrap(session, fn view ->
      view
      |> element("button[aria-label='Delete'][phx-value-item-id='#{user.id}']")
      |> render_click()
    end)
  end

  defp click_show_action(session) do
    unwrap(session, fn view -> view |> element("#item-action-user_soft_delete") |> render_click() end)
  end

  defp submit_reason(session, reason) do
    unwrap(session, fn view -> view |> form("#resource-form", change: %{reason: reason}) |> render_submit() end)
  end
end
