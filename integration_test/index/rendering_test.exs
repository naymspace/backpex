defmodule Backpex.Integration.Index.RenderingTest do
  use Backpex.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "index view" do
    test "renders the title, the resource buttons, the pagination info and a row per item", %{conn: conn} do
      insert_list(3, :tag)

      conn
      |> visit(~p"/admin/tags")
      |> assert_has("h1", text: "Tags", exact: true)
      |> assert_has("button", text: "New Tag", exact: true)
      |> assert_has("button[disabled]", text: "Delete", exact: true)
      |> assert_has("div", text: "Items 1 to 3 (3 total)", exact: true)
      |> assert_has("table tbody tr", count: 3)
    end

    test "enables the bulk delete button when an item is selected", %{conn: conn} do
      [tag | _tags] = insert_list(3, :tag)

      conn
      |> visit(~p"/admin/tags")
      |> refute_has("button:not([disabled])", text: "Delete")
      |> check("#select-input-#{tag.id}", "Select item with id: #{tag.id}")
      |> assert_has("button:not([disabled])", text: "Delete", exact: true)
    end

    test "the show and edit item actions lead to the show and edit view", %{conn: conn} do
      tag = insert(:tag)

      conn
      |> visit(~p"/admin/tags")
      |> click_link("#item-action-show-#{tag.id}", "Show")
      |> assert_path(~p"/admin/tags/#{tag.id}/show")

      conn
      |> visit(~p"/admin/tags")
      |> click_link("#item-action-edit-#{tag.id}", "Edit")
      |> assert_path(~p"/admin/tags/#{tag.id}/edit")
    end

    test "lists only the items of the item_query scope", %{conn: conn} do
      insert(:user, username: "active_user")
      insert(:user, username: "deleted_user", deleted_at: DateTime.utc_now(:second))

      conn
      |> visit(~p"/admin/users")
      |> assert_has("table tbody tr", count: 1)
      |> assert_has("input[value='active_user']")
      |> refute_has("input[value='deleted_user']")
    end
  end

  describe "edit item action" do
    test "leads back to the current index and show view", %{conn: conn} do
      post = insert(:post)

      conn
      |> visit(~p"/admin/posts?#{%{"page" => "1", "per_page" => "50"}}")
      |> assert_has("a#item-action-edit-#{post.id}[href*='return_to='][href*='per_page%3D50']")

      conn
      |> visit(~p"/admin/posts/#{post.id}/show")
      |> assert_has("a#item-action-edit[href*='return_to=%2Fadmin%2Fposts%2F#{post.id}%2Fshow']")
    end
  end

  describe "field components" do
    test "are not updated when an assign outside of the table changes", %{conn: conn} do
      [post | _posts] = insert_list(3, :post)

      {:error, {:live_redirect, %{to: path}}} = live(conn, ~p"/admin/posts")
      {:ok, view, _html} = live(conn, path)

      test_pid = self()
      handler_id = {__MODULE__, make_ref()}

      :telemetry.attach(
        handler_id,
        [:phoenix, :live_component, :update, :start],
        fn _event, _measurements, %{component: component}, _config ->
          if self() == view.pid, do: send(test_pid, {:updated, component})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      render_click(view, "toggle_metrics", %{})

      refute_received {:updated, _component}

      # The fields are updated when their item changes, so the handler above does receive updates.
      post = post |> Ecto.Changeset.change(title: "Changed title") |> Repo.update!()
      send(view.pid, {"backpex:updated", post})
      render(view)

      assert_received {:updated, _component}
    end
  end
end
