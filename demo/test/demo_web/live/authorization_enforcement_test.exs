defmodule DemoWeb.Live.AuthorizationEnforcementTest do
  @moduledoc """
  End-to-end checks that Backpex enforces `can?/3` server-side.

  Every test here forges an event the UI would never send: the buttons are hidden or disabled, so
  the only way to reach these code paths is a tampered payload.
  """
  use DemoWeb.ConnCase, async: false

  import Demo.EctoFactory
  import Phoenix.LiveViewTest

  alias Demo.Repo
  alias Demo.ShortLink
  alias Demo.User
  alias Phoenix.LiveView.Socket

  @moduletag :capture_log

  setup do
    # `live/2` links the LiveView to the test process. These tests deliberately make it crash, so
    # the EXIT signal has to arrive as a message instead of killing the test.
    Process.flag(:trap_exit, true)

    :ok
  end

  defp assign_socket(assigns) do
    Enum.reduce(assigns, %Socket{}, fn {key, value}, socket ->
      Phoenix.Component.assign(socket, key, value)
    end)
  end

  describe "forged item actions on a resource that denies the action" do
    setup do
      product = insert(:product)

      {:ok, short_link} =
        Repo.insert(%ShortLink{short_key: "forgedkey", url: "https://example.com", product_id: product.id})

      %{short_link: short_link}
    end

    test "raises ForbiddenError and keeps the record", %{conn: conn, short_link: short_link} do
      {:ok, view, _html} = live(conn, ~p"/admin/short-links")

      assert {{%Backpex.ForbiddenError{}, _stacktrace}, _mfa} =
               catch_exit(
                 render_click(view, "item-action", %{"action-key" => "delete", "item-id" => short_link.short_key})
               )

      assert Repo.get_by(ShortLink, short_key: "forgedkey")
    end
  end

  describe "forged item actions with a confirmation modal" do
    test "an unauthorized item raises before the modal opens", %{conn: conn} do
      admin = insert(:user, %{role: :admin})

      {:ok, view, _html} = live(conn, ~p"/admin/users")

      assert {{%Backpex.ForbiddenError{}, _stacktrace}, _mfa} =
               catch_exit(
                 render_click(view, "item-action", %{"action-key" => "user_soft_delete", "item-id" => admin.id})
               )

      assert Repo.get(User, admin.id).deleted_at == nil
    end

    test "a nonexistent item id raises NoResultsError", %{conn: conn} do
      insert(:user)

      {:ok, view, _html} = live(conn, ~p"/admin/users")

      assert {{%Backpex.NoResultsError{}, _stacktrace}, _mfa} =
               catch_exit(render_click(view, "item-action", %{"action-key" => "user_soft_delete", "item-id" => "0"}))
    end
  end

  describe "forged action keys" do
    test "an unknown key on a row raises NoResultsError, not ArgumentError", %{conn: conn} do
      user = insert(:user)

      {:ok, view, _html} = live(conn, ~p"/admin/users")

      assert {{%Backpex.NoResultsError{}, _stacktrace}, _mfa} =
               catch_exit(
                 render_click(view, "item-action", %{
                   "action-key" => "no_such_backpex_item_action_key",
                   "item-id" => user.id
                 })
               )
    end

    test "an unknown key on the toolbar raises NoResultsError, not ArgumentError", %{conn: conn} do
      insert(:user)

      {:ok, view, _html} = live(conn, ~p"/admin/users")

      assert {{%Backpex.NoResultsError{}, _stacktrace}, _mfa} =
               catch_exit(render_click(view, "item-action", %{"action-key" => "another_missing_action_key"}))
    end
  end

  describe "forged selection ids" do
    test "an unknown id is ignored and never enters the selection", %{conn: conn} do
      user = insert(:user)

      {:ok, view, _html} = live(conn, ~p"/admin/users")

      # A nil in `selected_items` would blow up in DemoWeb.UserLive.can?/3 on the next render.
      render_click(view, "update-selected-items", %{"id" => "0"})

      assert has_element?(view, "button[phx-value-action-key='user_soft_delete'][disabled]")
      refute has_element?(view, "#select-input-#{user.id}[checked]")

      render_click(view, "update-selected-items", %{"id" => user.id})

      assert has_element?(view, "#select-input-#{user.id}[checked]")
      refute has_element?(view, "button[phx-value-action-key='user_soft_delete'][disabled]")
    end
  end

  describe "mixed selections" do
    setup do
      %{user: insert(:user, %{role: :user}), admin: insert(:user, %{role: :admin})}
    end

    test "disable the bulk action button", %{conn: conn, user: user, admin: admin} do
      {:ok, view, _html} = live(conn, ~p"/admin/users")

      render_click(view, "update-selected-items", %{"id" => user.id})
      refute has_element?(view, "button[phx-value-action-key='user_soft_delete'][disabled]")

      render_click(view, "update-selected-items", %{"id" => admin.id})
      assert has_element?(view, "button[phx-value-action-key='user_soft_delete'][disabled]")
    end

    test "raise ForbiddenError when the bulk action is forged anyway", %{conn: conn, user: user, admin: admin} do
      {:ok, view, _html} = live(conn, ~p"/admin/users")

      render_click(view, "update-selected-items", %{"id" => user.id})
      render_click(view, "update-selected-items", %{"id" => admin.id})

      assert {{%Backpex.ForbiddenError{}, _stacktrace}, _mfa} =
               catch_exit(render_click(view, "item-action", %{"action-key" => "user_soft_delete"}))

      assert Repo.get(User, user.id).deleted_at == nil
      assert Repo.get(User, admin.id).deleted_at == nil
    end

    test "are re-checked on submit when the selection is widened after the modal opened", %{
      conn: conn,
      user: user,
      admin: admin
    } do
      {:ok, view, _html} = live(conn, ~p"/admin/users")

      render_click(view, "update-selected-items", %{"id" => user.id})
      render_click(view, "item-action", %{"action-key" => "user_soft_delete"})

      assert has_element?(view, "#resource-form")

      # The authorization state changes while the modal is open. Before the submit gate existed,
      # the unauthorized item was silently filtered out and the action reported success.
      render_click(view, "update-selected-items", %{"id" => admin.id})

      assert {{%Backpex.ForbiddenError{}, _stacktrace}, _mfa} =
               view
               |> form("#resource-form", change: %{reason: "widened after opening"})
               |> render_submit()
               |> catch_exit()

      assert Repo.get(User, user.id).deleted_at == nil
      assert Repo.get(User, admin.id).deleted_at == nil
    end
  end

  describe "rescue clauses in item actions" do
    test "the built-in delete action reraises ForbiddenError instead of flashing it" do
      product = insert(:product)

      {:ok, short_link} =
        Repo.insert(%ShortLink{short_key: "rescuekey", url: "https://example.com", product_id: product.id})

      socket = assign_socket(live_resource: DemoWeb.ShortLinkLive, item_action_key: :delete)

      assert_raise Backpex.ForbiddenError, fn ->
        Backpex.ItemActions.Delete.handle(socket, [short_link], %{})
      end

      assert Repo.get_by(ShortLink, short_key: "rescuekey")
    end

    test "the demo soft delete action reraises ForbiddenError instead of flashing it" do
      admin = insert(:user, %{role: :admin})

      socket = assign_socket(live_resource: DemoWeb.UserLive, item_action_key: :user_soft_delete)

      assert_raise Backpex.ForbiddenError, fn ->
        DemoWeb.ItemActions.UserSoftDelete.handle(socket, [admin], %{})
      end

      assert Repo.get(User, admin.id).deleted_at == nil
    end
  end
end
