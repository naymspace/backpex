defmodule Backpex.Integration.Authorization.SelectionTest do
  @moduledoc """
  Checks that the index selection only ever holds items an action may apply to, and that it follows the rows it points
  at, so bulk actions are authorized against the current records.
  """
  # The LiveViews subscribe to the PubSub topic of their LiveResource, which other tests broadcast to. Their events
  # would reload the list that a test here refutes a reload of, so these tests must not run concurrently with them.
  use Backpex.ConnCase, async: false

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias Backpex.Test.User

  @mixed_selection_title "Your selection contains items you may not apply this action to."
  @empty_selection_title "Select at least one item to use this action."

  setup do
    # `visit/2` links the LiveView to the test process. Some tests deliberately make it crash, so the EXIT signal has to
    # arrive as a message instead of killing the test.
    Process.flag(:trap_exit, true)

    :ok
  end

  describe "forged selection ids" do
    test "an unknown id is ignored and never enters the selection", %{conn: conn} do
      user = insert(:user)

      conn
      |> visit(~p"/admin/users")
      # A nil in `selected_items` would blow up in `Backpex.Test.UserLive.can?/3` on the next render.
      |> forge_selection("0")
      |> assert_has("button[phx-value-action-key='user_soft_delete'][disabled]")
      |> refute_has("#select-input-#{user.id}[checked]")
      |> check("Select item with id: #{user.id}")
      |> assert_has("#select-input-#{user.id}[checked]")
      |> refute_has("button[phx-value-action-key='user_soft_delete'][disabled]")
    end
  end

  describe "mixed selections" do
    setup do
      %{user: insert(:user, %{role: :user}), admin: insert(:user, %{role: :admin})}
    end

    test "disable the bulk action button and say why", %{conn: conn, user: user, admin: admin} do
      conn
      |> visit(~p"/admin/users")
      |> check("Select item with id: #{user.id}")
      |> refute_has("button[phx-value-action-key='user_soft_delete'][disabled]")
      # The admin's checkbox is disabled in the UI, so this selection can only be built by forging the event — but the
      # button must still explain itself rather than being a dead end.
      |> forge_selection(admin.id)
      |> assert_has("button[phx-value-action-key='user_soft_delete'][disabled]")
      |> assert_has("button[phx-value-action-key='user_soft_delete'][title='#{@mixed_selection_title}']")
    end

    test "an item no action applies to cannot be selected", %{conn: conn, user: user, admin: admin} do
      conn
      |> visit(~p"/admin/users")
      # `user_soft_delete` is the only bulk action on users and it is denied for admins, so an admin row can never take
      # part in one.
      |> assert_has("#select-input-#{admin.id}[disabled]")
      |> refute_has("#select-input-#{user.id}[disabled]")
      |> assert_has("#select-input-#{admin.id}[title='No action is available for this item.']")
    end

    test "select all skips items no action applies to", %{conn: conn, user: user, admin: admin} do
      conn
      |> visit(~p"/admin/users")
      |> check("Select all items")
      |> assert_has("#select-input-#{user.id}[checked]")
      |> refute_has("#select-input-#{admin.id}[checked]")
      # A select-all that produced an unusable selection would be the dead end this avoids.
      |> refute_has("button[phx-value-action-key='user_soft_delete'][disabled]")
    end

    test "empty selections say what to do instead of just being disabled", %{conn: conn} do
      conn
      |> visit(~p"/admin/users")
      |> assert_has("button[phx-value-action-key='user_soft_delete'][title='#{@empty_selection_title}']")
    end

    test "raise ForbiddenError when the bulk action is forged anyway", %{conn: conn, user: user, admin: admin} do
      session =
        conn
        |> visit(~p"/admin/users")
        |> check("Select item with id: #{user.id}")
        |> forge_selection(admin.id)

      assert {{%Backpex.ForbiddenError{}, _stacktrace}, _mfa} =
               catch_exit(unwrap(session, &render_click(&1, "item-action", %{"action-key" => "user_soft_delete"})))

      assert Repo.get(User, user.id).deleted_at == nil
      assert Repo.get(User, admin.id).deleted_at == nil
    end

    test "are re-checked on submit when the selection is widened after the modal opened", %{
      conn: conn,
      user: user,
      admin: admin
    } do
      session =
        conn
        |> visit(~p"/admin/users")
        |> check("Select item with id: #{user.id}")
        |> click_button("Delete")
        |> assert_has("#resource-form")
        # The authorization state changes while the modal is open. Before the submit gate existed, the unauthorized
        # item was silently filtered out and the action reported success.
        |> forge_selection(admin.id)
        |> fill_in("Reason", with: "widened after opening")

      assert {{%Backpex.ForbiddenError{}, _stacktrace}, _mfa} = catch_exit(submit(session))

      assert Repo.get(User, user.id).deleted_at == nil
      assert Repo.get(User, admin.id).deleted_at == nil
    end
  end

  describe "the selection follows the rows it points at" do
    setup %{conn: conn} do
      user = insert(:user, %{role: :user})

      session =
        conn
        |> visit(~p"/admin/users")
        |> check("Select item with id: #{user.id}")
        |> refute_has("button[phx-value-action-key='user_soft_delete'][disabled]")

      %{user: user, session: session}
    end

    test "an updated row is replaced in the selection, not only in the table", %{user: user, session: session} do
      user |> Ecto.Changeset.change(role: :admin) |> Repo.update!()

      session
      |> broadcast({"backpex:updated", user})
      # The button reads the *selection* to decide. If the selection still held the `role: :user` snapshot it would stay
      # enabled and lead straight into the submit gate.
      |> assert_has("button[phx-value-action-key='user_soft_delete'][title='#{@mixed_selection_title}']")
    end

    test "a deleted row leaves the selection", %{user: user, session: session} do
      Repo.delete!(user)

      session
      |> broadcast({"backpex:deleted", user})
      |> assert_has("button[phx-value-action-key='user_soft_delete'][title='#{@empty_selection_title}']")
    end

    test "a row that left the item query's scope leaves the selection too", %{user: user, session: session} do
      # An update can take a row out of scope just as a delete removes it. Re-reading it returns nothing, so it must not
      # linger in `items` or `selected_items` as `nil`.
      user |> Ecto.Changeset.change(deleted_at: DateTime.utc_now(:second)) |> Repo.update!()

      session
      |> broadcast({"backpex:updated", user})
      |> refute_has("#select-input-#{user.id}")
      |> assert_has("button[phx-value-action-key='user_soft_delete'][title='#{@empty_selection_title}']")
    end

    test "an out-of-scope update for a row this page never showed does not reload the list", %{
      user: user,
      session: session
    } do
      out_of_scope = insert(:user, %{deleted_at: DateTime.utc_now(:second)})
      # Changed without a broadcast, so the new name only shows up if the view re-runs its list query.
      user |> Ecto.Changeset.change(username: "renamed_unannounced") |> Repo.update!()

      session
      |> broadcast({"backpex:updated", out_of_scope})
      # Usernames render as the values of their index-edit inputs.
      |> refute_has("input", value: "renamed_unannounced")
      |> assert_has("input", value: user.username)
    end
  end

  describe "a row on another page that goes away" do
    # Users show 15 per page, so page 2 holds the last 5 of these. Once one of the first 15 is gone, page 2 must shrink
    # to 4 rows.
    setup %{conn: conn} do
      insert_list(20, :user)

      # `Backpex.Test.UserLive` orders by username, so the first one is on page 1.
      off_page_user = User |> order_by(asc: :username) |> limit(1) |> Repo.one!()

      session =
        conn
        |> visit(~p"/admin/users?page=2")
        |> assert_has("div", text: "(20 total)")
        |> assert_has("table tbody tr", count: 5)
        |> refute_has("#select-input-#{off_page_user.id}")

      %{session: session, off_page_user: off_page_user}
    end

    test "updates the total and shifts the rows when it leaves the item query's scope", %{
      session: session,
      off_page_user: off_page_user
    } do
      off_page_user |> Ecto.Changeset.change(deleted_at: DateTime.utc_now(:second)) |> Repo.update!()

      session
      |> broadcast({"backpex:updated", off_page_user})
      |> assert_has("div", text: "(19 total)")
      |> assert_has("table tbody tr", count: 4)
    end

    test "updates the total and shifts the rows when it is deleted", %{
      session: session,
      off_page_user: off_page_user
    } do
      Repo.delete!(off_page_user)

      session
      |> broadcast({"backpex:deleted", off_page_user})
      |> assert_has("div", text: "(19 total)")
      |> assert_has("table tbody tr", count: 4)
    end
  end

  # The checkbox of an id that is not on the page, or that the UI disables, can only be clicked by forging the event.
  defp forge_selection(session, id) do
    unwrap(session, &render_click(&1, "update-selected-items", %{"id" => id}))
  end

  # Delivers a PubSub message the way the LiveView receives it, without going through the endpoint.
  defp broadcast(session, message) do
    unwrap(session, fn view ->
      send(view.pid, message)
      render(view)
    end)
  end
end
