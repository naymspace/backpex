defmodule DemoWeb.Live.Post.NewLiveTest do
  use DemoWeb.ConnCase, async: false

  import Demo.EctoFactory
  import Phoenix.LiveViewTest

  describe "posts live resource new" do
    test "is rendered", %{conn: conn} do
      conn
      |> visit(~p"/admin/posts/new")
      |> assert_has("h1", text: "New Post", exact: true)
      |> assert_has("form#resource-form")
      |> assert_has("label", text: "Title")
      |> assert_has("label", text: "Body")
      |> assert_has("label", text: "Published")
    end

    test "creates post with title and body", %{conn: conn} do
      user = insert(:user)
      category = insert(:category)

      conn
      |> visit(~p"/admin/posts/new")
      |> unwrap(fn view ->
        view
        |> form("#resource-form",
          change: %{
            title: "New Test Post",
            body: "This is the post body content",
            user_id: user.id,
            category_id: category.id
          }
        )
        |> put_submitter("button[value=save]")
        |> render_submit()
      end)
      |> assert_path(~p"/admin/posts")
    end

    test "shows BelongsTo user select", %{conn: conn} do
      insert(:user)

      conn
      |> visit(~p"/admin/posts/new")
      |> assert_has("label", text: "Author")
      |> assert_has("select[name='change[user_id]']")
    end

    test "shows BelongsTo category select", %{conn: conn} do
      insert(:category)

      conn
      |> visit(~p"/admin/posts/new")
      |> assert_has("label", text: "Category")
      |> assert_has("select[name='change[category_id]']")
    end

    test "shows HasMany tags field", %{conn: conn} do
      insert(:tag)

      conn
      |> visit(~p"/admin/posts/new")
      # HasMany fields render their labels as spans
      |> assert_has("span", text: "Tags")
    end

    test "conditional visibility: likes field hidden when show_likes is false", %{conn: conn} do
      conn
      |> visit(~p"/admin/posts/new")
      # Initially show_likes is false, so likes field should not be visible
      |> refute_has("input[name='change[likes]']")
    end

    test "title required shows error on submit", %{conn: conn} do
      conn
      |> visit(~p"/admin/posts/new")
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
