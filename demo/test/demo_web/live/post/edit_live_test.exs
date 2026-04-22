defmodule DemoWeb.Live.Post.EditLiveTest do
  use DemoWeb.ConnCase, async: false

  import Demo.EctoFactory
  import Phoenix.LiveViewTest

  describe "posts live resource edit" do
    test "is rendered", %{conn: conn} do
      post = insert(:post)

      conn
      |> visit(~p"/admin/posts/#{post.id}/edit")
      |> assert_has("h1", text: "Edit Post", exact: true)
      |> assert_has("button", text: "Cancel", exact: true)
      |> assert_has("button", text: "Save", exact: true)
    end

    test "submit form", %{conn: conn} do
      post = insert(:post, %{title: "Old Title", published: true})

      conn
      |> visit(~p"/admin/posts/#{post.id}/edit")
      |> unwrap(fn view ->
        view
        |> form("#resource-form", change: %{title: "New Title"})
        |> put_submitter("button[value=save]")
        |> render_submit()
      end)
      |> assert_path(~p"/admin/posts")
      |> assert_has("table tbody tr", count: 1)
      |> assert_has("p", text: "New Title", exact: true)
    end

    test "editing with invalid data shows error", %{conn: conn} do
      post = insert(:post, %{title: "Original Title"})

      conn
      |> visit(~p"/admin/posts/#{post.id}/edit")
      |> unwrap(fn view ->
        view
        |> form("#resource-form", change: %{title: ""})
        |> put_submitter("button[value=save]")
        |> render_submit()
      end)
      |> assert_has("form#resource-form")
      |> assert_has("p", text: "can't be blank")
    end
  end
end
