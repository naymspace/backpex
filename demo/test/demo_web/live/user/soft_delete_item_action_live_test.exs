defmodule DemoWeb.Live.User.SoftDeleteItemActionLiveTest do
  use DemoWeb.ConnCase, async: false

  import Demo.EctoFactory
  import Phoenix.LiveViewTest

  describe "user soft delete item action" do
    test "soft delete button is available from index", %{conn: conn} do
      user = insert(:user)

      conn
      |> visit(~p"/admin/users")
      |> assert_has("button[aria-label='Delete'][phx-value-item-id='#{user.id}']")
    end

    test "soft delete requires reason field", %{conn: conn} do
      user = insert(:user, %{username: "tobedeleted"})

      conn
      |> visit(~p"/admin/users")
      |> unwrap(fn view ->
        view
        |> element("button[aria-label='Delete'][phx-value-item-id='#{user.id}']")
        |> render_click()
      end)
      # The modal should show the reason field
      |> assert_has("label", text: "Reason")
      |> assert_has("textarea[name='change[reason]']")
    end

    test "soft delete from index works with reason", %{conn: conn} do
      user = insert(:user, %{username: "usertoremove"})

      conn
      |> visit(~p"/admin/users")
      # Username field is index_editable, so it renders as an input
      |> assert_has("input[value='usertoremove']")
      |> unwrap(fn view ->
        view
        |> element("button[aria-label='Delete'][phx-value-item-id='#{user.id}']")
        |> render_click()
      end)
      |> unwrap(fn view ->
        view
        |> form("#resource-form", change: %{reason: "User requested deletion"})
        |> render_submit()
      end)
      |> assert_path(~p"/admin/users")
      |> refute_has("input[value='usertoremove']")
      |> assert_has("div", text: "has been deleted successfully")
    end

    test "soft delete sets deleted_at timestamp", %{conn: conn} do
      user = insert(:user)

      conn
      |> visit(~p"/admin/users")
      |> unwrap(fn view ->
        view
        |> element("button[aria-label='Delete'][phx-value-item-id='#{user.id}']")
        |> render_click()
      end)
      |> unwrap(fn view ->
        view
        |> form("#resource-form", change: %{reason: "Testing soft delete"})
        |> render_submit()
      end)

      # Verify the user has deleted_at set in the database
      updated_user = Demo.Repo.get(Demo.User, user.id)
      assert updated_user.deleted_at != nil
    end

    test "soft delete from show view works", %{conn: conn} do
      user = insert(:user, %{username: "showuser"})

      conn
      |> visit(~p"/admin/users/#{user.id}/show")
      |> assert_has("dd", text: "showuser")
      |> assert_has("#item-action-user_soft_delete")
      |> unwrap(fn view ->
        view
        |> element("#item-action-user_soft_delete")
        |> render_click()
      end)
      |> unwrap(fn view ->
        view
        |> form("#resource-form", change: %{reason: "Deleting from show view"})
        |> render_submit()
      end)
      |> assert_path(~p"/admin/users")
      |> refute_has("td", text: "showuser")
    end

    test "admin users cannot be soft deleted", %{conn: conn} do
      admin_user = insert(:user, %{username: "adminuser", role: :admin})

      conn
      |> visit(~p"/admin/users")
      # Username field is index_editable, so it renders as an input
      |> assert_has("input[value='adminuser']")
      # The delete button should not be available for admin users
      |> refute_has("button[aria-label='Delete'][phx-value-item-id='#{admin_user.id}']")
    end

    test "admin users show view has no delete button", %{conn: conn} do
      admin_user = insert(:user, %{role: :admin})

      conn
      |> visit(~p"/admin/users/#{admin_user.id}/show")
      |> refute_has("#item-action-user_soft_delete")
    end
  end
end
