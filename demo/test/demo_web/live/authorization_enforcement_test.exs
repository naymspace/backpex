defmodule DemoWeb.Live.AuthorizationEnforcementTest do
  @moduledoc """
  End-to-end checks that Backpex enforces `can?/3` server-side.

  Every test here forges an event the UI would never send: the buttons are hidden or disabled, so
  the only way to reach these code paths is a tampered payload.
  """
  use DemoWeb.ConnCase, async: false

  import Demo.EctoFactory
  import Phoenix.LiveViewTest

  alias Demo.Post
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

    test "disable the bulk action button and say why", %{conn: conn, user: user, admin: admin} do
      {:ok, view, _html} = live(conn, ~p"/admin/users")

      render_click(view, "update-selected-items", %{"id" => user.id})
      refute has_element?(view, "button[phx-value-action-key='user_soft_delete'][disabled]")

      # The admin's checkbox is disabled in the UI, so this selection can only be built by forging
      # the event — but the button must still explain itself rather than being a dead end.
      render_click(view, "update-selected-items", %{"id" => admin.id})

      assert has_element?(view, "button[phx-value-action-key='user_soft_delete'][disabled]")

      assert has_element?(
               view,
               "button[phx-value-action-key='user_soft_delete'][title='Your selection contains items you may not apply this action to.']"
             )
    end

    test "an item no action applies to cannot be selected", %{conn: conn, user: user, admin: admin} do
      {:ok, view, _html} = live(conn, ~p"/admin/users")

      # `user_soft_delete` is the only bulk action on users and it is denied for admins, so an
      # admin row can never take part in one.
      assert has_element?(view, "#select-input-#{admin.id}[disabled]")
      refute has_element?(view, "#select-input-#{user.id}[disabled]")

      assert has_element?(
               view,
               "#select-input-#{admin.id}[title='No action is available for this item.']"
             )
    end

    test "select all skips items no action applies to", %{conn: conn, user: user, admin: admin} do
      {:ok, view, _html} = live(conn, ~p"/admin/users")

      render_click(view, "toggle-item-selection", %{})

      assert has_element?(view, "#select-input-#{user.id}[checked]")
      refute has_element?(view, "#select-input-#{admin.id}[checked]")

      # A select-all that produced an unusable selection would be the dead end this avoids.
      refute has_element?(view, "button[phx-value-action-key='user_soft_delete'][disabled]")
    end

    test "empty selections say what to do instead of just being disabled", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/users")

      assert has_element?(
               view,
               "button[phx-value-action-key='user_soft_delete'][title='Select at least one item to use this action.']"
             )
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

  describe "the selection is re-read before the submit gate" do
    setup %{conn: conn} do
      user = insert(:user, %{role: :user})

      {:ok, view, _html} = live(conn, ~p"/admin/users")

      # Select the row and open the confirm modal. From here on `selected_items` holds a snapshot
      # of the record as it was at this moment — every test below changes the row behind the
      # LiveView's back, without a broadcast, so nothing refreshes it.
      render_click(view, "update-selected-items", %{"id" => user.id})
      render_click(view, "item-action", %{"action-key" => "user_soft_delete"})

      assert has_element?(view, "#resource-form")

      %{user: user, view: view}
    end

    test "a record that turned unauthorized while the modal was open raises on submit", %{user: user, view: view} do
      # `DemoWeb.UserLive.can?/3` denies `:user_soft_delete` for admins. The snapshot in
      # `selected_items` still says `role: :user`, so only re-reading the row catches this.
      user |> Ecto.Changeset.change(role: :admin) |> Repo.update!()

      assert {{%Backpex.ForbiddenError{}, _stacktrace}, _mfa} =
               view
               |> form("#resource-form", change: %{reason: "promoted while the modal was open"})
               |> render_submit()
               |> catch_exit()

      assert Repo.get(User, user.id).deleted_at == nil
    end

    test "a record deleted while the modal was open raises NoResultsError on submit", %{user: user, view: view} do
      Repo.delete!(user)

      assert {{%Backpex.NoResultsError{}, _stacktrace}, _mfa} =
               view
               |> form("#resource-form", change: %{reason: "deleted while the modal was open"})
               |> render_submit()
               |> catch_exit()
    end

    test "a record that left the item query's scope raises NoResultsError on submit", %{user: user, view: view} do
      # `DemoWeb.UserLive.item_query/3` hides soft-deleted users, so this row is gone as far as the
      # resource is concerned even though it is still in the table.
      user |> Ecto.Changeset.change(deleted_at: DateTime.utc_now(:second)) |> Repo.update!()

      assert {{%Backpex.NoResultsError{}, _stacktrace}, _mfa} =
               view
               |> form("#resource-form", change: %{reason: "soft deleted while the modal was open"})
               |> render_submit()
               |> catch_exit()
    end

    test "handle/3 gets the re-read record, not the snapshot", %{conn: conn, user: user, view: view} do
      # The user had no posts when the row was selected, so the snapshot's `posts` is `[]`.
      # `DemoWeb.ItemActions.UserSoftDelete.handle/3` nullifies `user_id` on the posts it is
      # handed — the post below can only be reached through the re-read record.
      post = insert(:post, user: user)

      result =
        view
        |> form("#resource-form", change: %{reason: "still allowed"})
        |> render_submit()

      assert {:ok, _view, html} = follow_redirect(result, conn)
      assert html =~ "User has been deleted successfully."

      assert Repo.get(User, user.id).deleted_at != nil
      assert Repo.get(Post, post.id).user_id == nil
    end
  end

  describe "resource actions" do
    test "an authorized submit runs the action", %{conn: conn} do
      insert(:user)

      {:ok, view, _html} = live(conn, ~p"/admin/users/invite/resource-action")

      result =
        view
        |> form("#resource-form", change: %{text: "Please join us"})
        |> render_submit(%{"change" => %{"users" => ["user_id_alex"]}, "save-type" => "save"})

      assert {:ok, _view, html} = follow_redirect(result, conn)
      assert html =~ "An email has been successfully sent"
    end

    test "the submit gate raises when the action is denied while the form is open" do
      # The route already refuses an action the user may not open, so the only way to reach the
      # submit gate with a denial is a permission that changed while the modal was open. Drive the
      # form component directly rather than pretend a demo resource can do that.
      socket =
        assign_socket(
          live_action: :resource_action,
          action_type: :resource,
          live_resource: DemoWeb.InvoiceLive,
          resource_action: %{module: DemoWeb.ResourceActions.Email},
          resource_action_id: :invite,
          fields: [],
          item: %{},
          return_to: "/admin/invoices"
        )

      assert_raise Backpex.ForbiddenError, fn ->
        Backpex.FormComponent.handle_event("save", %{"change" => %{}, "save-type" => "save"}, socket)
      end
    end
  end
end
