defmodule Backpex.Integration.Form.FormActionsTest do
  use Backpex.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Backpex.Test.Post

  describe "save and continue" do
    test "is offered next to the default actions", %{conn: conn} do
      conn
      |> visit(~p"/admin/posts/new")
      |> assert_has("#form-action-continue", text: "Save & Continue editing")
      |> refute_has("#form-action-show")
    end

    test "opens the edit view of the created item", %{conn: conn} do
      user = insert(:user)
      category = insert(:category)

      session =
        conn
        |> visit(~p"/admin/posts/new")
        |> unwrap(fn view ->
          view
          |> form("#resource-form",
            change: %{title: "Continue Post", body: "Body", user_id: user.id, category_id: category.id}
          )
          |> put_submitter("button[value=continue]")
          |> render_submit()
        end)

      post = Repo.get_by!(Post, title: "Continue Post")

      session
      |> assert_path(~p"/admin/posts/#{post.id}/edit")
      |> assert_has("h1", text: "Edit Post", exact: true)
    end
  end

  describe "custom form action" do
    test "saves the item and leads where return_to/5 says", %{conn: conn} do
      post = insert(:post, title: "Old Title")

      conn
      |> visit(~p"/admin/posts/#{post.id}/edit")
      |> assert_has("#form-action-show", text: "Save & Show")
      |> unwrap(fn view ->
        view
        |> form("#resource-form", change: %{title: "New Title"})
        |> put_submitter("button[value=show]")
        |> render_submit()
      end)
      |> assert_path(~p"/admin/posts/#{post.id}/show")
      |> assert_has("dd", text: "New Title")
    end
  end
end
