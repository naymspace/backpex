defmodule Backpex.Integration.Authorization.ItemActionsTest do
  @moduledoc """
  Checks that item actions enforce `can?/3` server-side.

  Every test here forges an event the UI would never send: the buttons are hidden or disabled, so the only way to reach
  these code paths is a tampered payload.
  """
  use Backpex.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Backpex.Test.Post
  alias Backpex.Test.ShortLink
  alias Backpex.Test.User

  @moduletag :capture_log

  setup do
    # `live/2` links the LiveView to the test process. These tests deliberately make it crash, so the EXIT signal has to
    # arrive as a message instead of killing the test.
    Process.flag(:trap_exit, true)

    :ok
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

  describe "the selection is re-read before the submit gate" do
    setup %{conn: conn} do
      user = insert(:user, %{role: :user})

      {:ok, view, _html} = live(conn, ~p"/admin/users")

      # Select the row and open the confirm modal. From here on `selected_items` holds a snapshot of the record as it
      # was at this moment — every test below changes the row behind the LiveView's back, without a broadcast, so
      # nothing refreshes it.
      render_click(view, "update-selected-items", %{"id" => user.id})
      render_click(view, "item-action", %{"action-key" => "user_soft_delete"})

      assert has_element?(view, "#resource-form")

      %{user: user, view: view}
    end

    test "a record that turned unauthorized while the modal was open raises on submit", %{user: user, view: view} do
      # `Backpex.Test.UserLive.can?/3` denies `:user_soft_delete` for admins. The snapshot in `selected_items` still
      # says `role: :user`, so only re-reading the row catches this.
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
      # `Backpex.Test.UserLive.item_query/3` hides soft-deleted users, so this row is gone as far as the resource is
      # concerned even though it is still in the table.
      user |> Ecto.Changeset.change(deleted_at: DateTime.utc_now(:second)) |> Repo.update!()

      assert {{%Backpex.NoResultsError{}, _stacktrace}, _mfa} =
               view
               |> form("#resource-form", change: %{reason: "soft deleted while the modal was open"})
               |> render_submit()
               |> catch_exit()
    end

    test "handle/3 gets the re-read record, not the snapshot", %{conn: conn, user: user, view: view} do
      # The user had no posts when the row was selected, so the snapshot's `posts` is `[]`.
      # `Backpex.Test.ItemActions.UserSoftDelete.handle/3` nullifies `user_id` on the posts it is handed — the post below
      # can only be reached through the re-read record.
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
end
