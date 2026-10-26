defmodule Backpex.Integration.Form.FormActionsTest do
  use Backpex.ConnCase, async: true

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
        |> fill_in("Title", with: "Continue Post")
        |> fill_in("Body", with: "Body")
        |> select("Author", option: "#{user.first_name} #{user.last_name}")
        |> select("Category", option: category.name)
        |> click_button("Save & Continue editing")

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
      |> fill_in("Title", with: "New Title")
      |> click_button("Save & Show")
      |> assert_path(~p"/admin/posts/#{post.id}/show")
      |> assert_has("dd", text: "New Title")
    end
  end
end
