defmodule Backpex.Integration.Form.SaveTest do
  use Backpex.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Backpex.Test.Tag
  alias Backpex.Test.User

  test "creates an item and returns to the index view", %{conn: conn} do
    conn
    |> visit(~p"/admin/tags/new")
    |> fill_in("Name", with: "Phoenix")
    |> click_button("Save")
    |> assert_path(~p"/admin/tags")
    |> assert_has("table tbody tr", count: 1)
    |> assert_has("p", text: "Phoenix", exact: true)
  end

  test "prefills the form with the item, updates it and returns to the index view", %{conn: conn} do
    tag = insert(:tag, name: "Elixir")

    conn
    |> visit(~p"/admin/tags/#{tag.id}/edit")
    |> assert_has("input", label: "Name", value: "Elixir")
    |> fill_in("Name", with: "Phoenix")
    |> click_button("Save")
    |> assert_path(~p"/admin/tags")
    |> assert_has("table tbody tr", count: 1)
    |> assert_has("p", text: "Phoenix", exact: true)
  end

  # The form holds the item as it was when the form was mounted. Every test changes the row behind the LiveView's back
  # and then saves the form.
  describe "an item that changed while the edit form was open" do
    setup %{conn: conn} do
      # `visit/2` links the LiveView to the test process. Some of these tests make it crash, so the EXIT signal has to
      # arrive as a message instead of killing the test.
      Process.flag(:trap_exit, true)

      user = insert(:user, username: "alice", avatar: "old.png")

      session =
        conn
        |> visit(~p"/admin/users/#{user.id}/edit")
        |> fill_in("Username", with: "bob")

      %{user: user, session: session}
    end

    test "is not updated when the user may no longer edit it", %{user: user, session: session} do
      # `Backpex.Test.UserLive.can?/3` denies `:edit` for the user named "locked".
      user |> Ecto.Changeset.change(username: "locked") |> Repo.update!()

      assert {{%Backpex.ForbiddenError{}, _stacktrace}, _mfa} = catch_exit(click_button(session, "Save"))

      assert Repo.get(User, user.id).username == "locked"
    end

    test "is not updated when it has left the scope of the item query", %{user: user, session: session} do
      # `Backpex.Test.UserLive.item_query/3` hides soft-deleted users.
      user |> Ecto.Changeset.change(deleted_at: DateTime.utc_now(:second)) |> Repo.update!()

      assert {{%Backpex.NoResultsError{}, _stacktrace}, _mfa} = catch_exit(click_button(session, "Save"))

      assert Repo.get(User, user.id).username == "alice"
    end

    test "raises NoResultsError when it was deleted", %{user: user, session: session} do
      Repo.delete!(user)

      assert {{%Backpex.NoResultsError{}, _stacktrace}, _mfa} = catch_exit(click_button(session, "Save"))
    end

    test "is saved with the values of the form and keeps the new values the form has no field for", %{
      user: user,
      session: session
    } do
      # The form has no field for the avatar, and its age field still holds the value the item had on mount.
      user |> Ecto.Changeset.change(avatar: "new.png", age: 40) |> Repo.update!()

      session
      |> click_button("Save")
      |> assert_path(~p"/admin/users")

      assert %User{username: "bob", avatar: "new.png", age: 30} = Repo.get(User, user.id)

      # The `item` assign of the socket that `on_item_updated/2` receives is the item as it was right before the save.
      assert_received {:on_item_updated, %User{username: "alice", avatar: "new.png", age: 40}, %User{username: "bob"}}
    end
  end

  # A submit without a submitter, e.g. `form.requestSubmit()` in a hook, sends the values without `save-type`.
  describe "without a submitter" do
    test "creates an item with the submitted values", %{conn: conn} do
      conn
      |> visit(~p"/admin/tags/new")
      |> unwrap(fn view -> view |> form("#resource-form", change: %{name: "Phoenix"}) |> render_submit() end)
      |> assert_path(~p"/admin/tags")
      |> assert_has("p", text: "Phoenix", exact: true)

      assert [%Tag{name: "Phoenix"}] = Repo.all(Tag)
    end

    test "updates the item with the submitted values", %{conn: conn} do
      tag = insert(:tag, name: "Elixir")

      conn
      |> visit(~p"/admin/tags/#{tag.id}/edit")
      |> unwrap(fn view -> view |> form("#resource-form", change: %{name: "Phoenix"}) |> render_submit() end)
      |> assert_path(~p"/admin/tags")
      |> assert_has("p", text: "Phoenix", exact: true)

      assert Repo.reload!(tag).name == "Phoenix"
    end
  end
end
