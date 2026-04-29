defmodule DemoWeb.Live.Post.IndexLiveTest do
  use DemoWeb.ConnCase, async: false

  import Demo.EctoFactory
  import Demo.Support.LiveResourceTests
  import Phoenix.LiveViewTest

  describe "posts live resource index" do
    test "is rendered", %{conn: conn} do
      insert_list(3, :post, published: true)

      conn
      |> visit(~p"/admin/posts")
      |> assert_has("h1", text: "Posts", exact: true)
      |> assert_has("button", text: "New Post", exact: true)
      |> assert_has("button[disabled]", text: "Delete", exact: true)
      |> assert_has("table tbody tr", count: 3)
    end

    test "renders posts with title", %{conn: conn} do
      post = insert(:post, %{title: "Test Post Title", published: true})

      conn
      |> visit(~p"/admin/posts")
      |> assert_has("td", text: post.title)
    end

    test "search finds posts by title", %{conn: conn} do
      insert(:post, %{title: "Alpha Post", published: true})
      insert(:post, %{title: "Beta Post", published: true})

      conn
      |> visit(~p"/admin/posts")
      |> assert_has(".table tbody tr", count: 2)
      |> unwrap(fn view ->
        view
        |> form("#index-search-form", index_search: %{value: "Alpha"})
        |> render_change()
      end)
      |> assert_has("table tbody tr", count: 1)
      |> assert_has("tr", text: "Alpha Post")
      |> refute_has("tr", text: "Beta Post")
    end

    test "metrics display total_likes value", %{conn: conn} do
      insert(:post, %{likes: 100, published: true})
      insert(:post, %{likes: 200, published: true})
      insert(:post, %{likes: 300, published: true})

      conn
      |> visit(~p"/admin/posts")
      |> assert_has("div", text: "Total likes")
      |> assert_has("div", text: "600 likes")
    end

    test "metrics display published posts count", %{conn: conn} do
      insert(:post, %{published: true})
      insert(:post, %{published: true})
      insert(:post, %{published: false})

      conn
      |> visit(~p"/admin/posts")
      |> assert_has("div", text: "Published Posts")
      |> assert_has("div", text: "2")
    end

    test "category select filter is available", %{conn: conn} do
      insert(:post)

      conn
      |> visit(~p"/admin/posts")
      |> assert_has("div", text: "Category")
    end

    test "likes range filter is available", %{conn: conn} do
      insert(:post)

      conn
      |> visit(~p"/admin/posts")
      |> assert_has("div", text: "Likes")
    end

    test "published filter shows only published posts by default", %{conn: conn} do
      insert(:post, %{title: "Published Post", published: true})
      insert(:post, %{title: "Draft Post", published: false})

      conn
      |> visit(~p"/admin/posts")
      # By default, published filter shows only published posts
      |> assert_has("table tbody tr", count: 1)
      |> assert_has("tr", text: "Published Post")
      |> refute_has("tr", text: "Draft Post")
    end

    test "basic functionality", %{conn: conn} do
      posts = insert_list(3, :post, published: true)

      test_table_rows_count(conn, ~p"/admin/posts", Enum.count(posts))
      test_delete_button_disabled_enabled(conn, ~p"/admin/posts", posts)
      test_show_action_redirect(conn, ~p"/admin/posts", posts)
      test_edit_action_redirect(conn, ~p"/admin/posts", posts)
    end
  end
end
