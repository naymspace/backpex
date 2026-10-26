defmodule Backpex.Integration.Authorization.SelectionTest do
  @moduledoc """
  Checks that the index selection only ever holds items an action may apply to, and that it follows the rows it points
  at, so bulk actions are authorized against the current records.
  """
  use Backpex.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Backpex.Test.User

  @moduletag :capture_log

  @mixed_selection_title "Your selection contains items you may not apply this action to."
  @empty_selection_title "Select at least one item to use this action."

  setup do
    # `live/2` links the LiveView to the test process. Some tests deliberately make it crash, so the EXIT signal has to
    # arrive as a message instead of killing the test.
    Process.flag(:trap_exit, true)

    :ok
  end

  describe "forged selection ids" do
    test "an unknown id is ignored and never enters the selection", %{conn: conn} do
      user = insert(:user)

      {:ok, view, _html} = live(conn, ~p"/admin/users")

      # A nil in `selected_items` would blow up in `Backpex.Test.UserLive.can?/3` on the next render.
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

      # The admin's checkbox is disabled in the UI, so this selection can only be built by forging the event — but the
      # button must still explain itself rather than being a dead end.
      render_click(view, "update-selected-items", %{"id" => admin.id})

      assert has_element?(view, "button[phx-value-action-key='user_soft_delete'][disabled]")
      assert has_element?(view, "button[phx-value-action-key='user_soft_delete'][title='#{@mixed_selection_title}']")
    end

    test "an item no action applies to cannot be selected", %{conn: conn, user: user, admin: admin} do
      {:ok, view, _html} = live(conn, ~p"/admin/users")

      # `user_soft_delete` is the only bulk action on users and it is denied for admins, so an admin row can never take
      # part in one.
      assert has_element?(view, "#select-input-#{admin.id}[disabled]")
      refute has_element?(view, "#select-input-#{user.id}[disabled]")

      assert has_element?(view, "#select-input-#{admin.id}[title='No action is available for this item.']")
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

      assert has_element?(view, "button[phx-value-action-key='user_soft_delete'][title='#{@empty_selection_title}']")
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

      # The authorization state changes while the modal is open. Before the submit gate existed, the unauthorized item
      # was silently filtered out and the action reported success.
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

  describe "the selection follows the rows it points at" do
    setup %{conn: conn} do
      user = insert(:user, %{role: :user})

      {:ok, view, _html} = live(conn, ~p"/admin/users")

      render_click(view, "update-selected-items", %{"id" => user.id})
      refute has_element?(view, "button[phx-value-action-key='user_soft_delete'][disabled]")

      %{user: user, view: view}
    end

    test "an updated row is replaced in the selection, not only in the table", %{user: user, view: view} do
      user |> Ecto.Changeset.change(role: :admin) |> Repo.update!()

      send(view.pid, {"backpex:updated", user})
      _html = render(view)

      # The button reads the *selection* to decide. If the selection still held the `role: :user` snapshot it would stay
      # enabled and lead straight into the submit gate.
      assert has_element?(view, "button[phx-value-action-key='user_soft_delete'][title='#{@mixed_selection_title}']")
    end

    test "a deleted row leaves the selection", %{user: user, view: view} do
      Repo.delete!(user)

      send(view.pid, {"backpex:deleted", user})
      _html = render(view)

      assert has_element?(view, "button[phx-value-action-key='user_soft_delete'][title='#{@empty_selection_title}']")
    end

    test "a row that left the item query's scope leaves the selection too", %{user: user, view: view} do
      # An update can take a row out of scope just as a delete removes it. Re-reading it returns nothing, so it must not
      # linger in `items` or `selected_items` as `nil`.
      user |> Ecto.Changeset.change(deleted_at: DateTime.utc_now(:second)) |> Repo.update!()

      send(view.pid, {"backpex:updated", user})
      html = render(view)

      refute html =~ "select-input-#{user.id}"
      assert has_element?(view, "button[phx-value-action-key='user_soft_delete'][title='#{@empty_selection_title}']")
    end

    test "an out-of-scope update for a row this page never showed does not reload the list", %{
      user: user,
      view: view
    } do
      out_of_scope = insert(:user, %{deleted_at: DateTime.utc_now(:second)})
      # Changed without a broadcast, so the new name only shows up if the view re-runs its list query.
      user |> Ecto.Changeset.change(username: "renamed_unannounced") |> Repo.update!()

      send(view.pid, {"backpex:updated", out_of_scope})
      html = render(view)

      refute html =~ "renamed_unannounced"
      assert html =~ user.username
    end
  end

  describe "a row on another page that goes away" do
    # Users show 15 per page, so page 2 holds the last 5 of these. Once one of the first 15 is gone, page 2 must shrink
    # to 4 rows.
    setup %{conn: conn} do
      users = insert_list(20, :user)

      {:ok, view, html} = live(conn, ~p"/admin/users?page=2")
      assert html =~ "(20 total)"
      assert row_count(html) == 5

      off_page_user = Enum.find(users, &(not (html =~ "select-input-#{&1.id}")))

      %{view: view, off_page_user: off_page_user}
    end

    test "updates the total and shifts the rows when it leaves the item query's scope", %{
      view: view,
      off_page_user: off_page_user
    } do
      off_page_user |> Ecto.Changeset.change(deleted_at: DateTime.utc_now(:second)) |> Repo.update!()

      send(view.pid, {"backpex:updated", off_page_user})
      html = render(view)

      assert html =~ "(19 total)"
      assert row_count(html) == 4
    end

    test "updates the total and shifts the rows when it is deleted", %{view: view, off_page_user: off_page_user} do
      Repo.delete!(off_page_user)

      send(view.pid, {"backpex:deleted", off_page_user})
      html = render(view)

      assert html =~ "(19 total)"
      assert row_count(html) == 4
    end
  end

  defp row_count(html) do
    html
    |> LazyHTML.from_document()
    |> LazyHTML.query("table tbody tr")
    |> Enum.count()
  end
end
