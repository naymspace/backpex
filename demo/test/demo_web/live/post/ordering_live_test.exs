defmodule DemoWeb.Live.Post.OrderingLiveTest do
  use DemoWeb.ConnCase, async: false

  import Demo.EctoFactory
  import Phoenix.LiveViewTest

  # Posts use default init_order: %{by: :id, direction: :asc}
  # The :tags field has orderable: false
  # Posts have a default published filter, so we always pass published: true

  describe "default ordering" do
    test "orders by id ascending by default", %{conn: conn} do
      insert(:post, title: "First Post", published: true)
      insert(:post, title: "Second Post", published: true)
      insert(:post, title: "Third Post", published: true)

      conn
      |> visit(~p"/admin/posts")
      |> assert_has("table tbody tr", count: 3)
      |> assert_has("table tbody tr:first-child td", text: "First Post")
      |> assert_has("table tbody tr:last-child td", text: "Third Post")
    end
  end

  describe "ordering via URL params" do
    test "orders by title ascending", %{conn: conn} do
      insert(:post, title: "Cherry", published: true)
      insert(:post, title: "Apple", published: true)
      insert(:post, title: "Banana", published: true)

      params = %{"order_by" => "title", "order_direction" => "asc", "filters" => %{"published" => ["published"]}}

      conn
      |> visit(~p"/admin/posts?#{params}")
      |> assert_has("table tbody tr", count: 3)
      |> assert_has("table tbody tr:first-child td", text: "Apple")
      |> assert_has("table tbody tr:last-child td", text: "Cherry")
    end

    test "orders by title descending", %{conn: conn} do
      insert(:post, title: "Cherry", published: true)
      insert(:post, title: "Apple", published: true)
      insert(:post, title: "Banana", published: true)

      params = %{"order_by" => "title", "order_direction" => "desc", "filters" => %{"published" => ["published"]}}

      conn
      |> visit(~p"/admin/posts?#{params}")
      |> assert_has("table tbody tr", count: 3)
      |> assert_has("table tbody tr:first-child td", text: "Cherry")
      |> assert_has("table tbody tr:last-child td", text: "Apple")
    end

    test "orders by likes descending", %{conn: conn} do
      insert(:post, title: "Popular", published: true, likes: 500)
      insert(:post, title: "Average", published: true, likes: 50)
      insert(:post, title: "New", published: true, likes: 1)

      params = %{"order_by" => "likes", "order_direction" => "desc", "filters" => %{"published" => ["published"]}}

      conn
      |> visit(~p"/admin/posts?#{params}")
      |> assert_has("table tbody tr", count: 3)
      |> assert_has("table tbody tr:first-child td", text: "Popular")
      |> assert_has("table tbody tr:last-child td", text: "New")
    end
  end

  describe "invalid ordering params" do
    test "falls back to default order_by for invalid order_by field", %{conn: conn} do
      insert(:post, title: "First Post", published: true)
      insert(:post, title: "Second Post", published: true)
      insert(:post, title: "Third Post", published: true)

      params = %{
        "order_by" => "nonexistent_field",
        "order_direction" => "asc",
        "filters" => %{"published" => ["published"]}
      }

      conn
      |> visit(~p"/admin/posts?#{params}")
      |> assert_has("table tbody tr", count: 3)
      |> assert_has("table tbody tr:first-child td", text: "First Post")
      |> assert_has("table tbody tr:last-child td", text: "Third Post")
    end

    test "falls back to default direction for invalid order_direction", %{conn: conn} do
      insert(:post, title: "Cherry", published: true)
      insert(:post, title: "Apple", published: true)
      insert(:post, title: "Banana", published: true)

      params = %{"order_by" => "title", "order_direction" => "INVALID", "filters" => %{"published" => ["published"]}}

      conn
      |> visit(~p"/admin/posts?#{params}")
      |> assert_has("table tbody tr", count: 3)
      # order_by=title is valid, direction falls back to default: asc
      |> assert_has("table tbody tr:first-child td", text: "Apple")
      |> assert_has("table tbody tr:last-child td", text: "Cherry")
    end
  end

  describe "ordering via column header click" do
    test "clicking Title column orders by title ascending", %{conn: conn} do
      insert(:post, title: "Cherry", published: true)
      insert(:post, title: "Apple", published: true)
      insert(:post, title: "Banana", published: true)

      conn
      |> visit(~p"/admin/posts")
      |> unwrap(fn view ->
        view
        |> element("a", "Title")
        |> render_click()
      end)
      |> assert_has("table tbody tr:first-child td", text: "Apple")
      |> assert_has("table tbody tr:last-child td", text: "Cherry")
    end

    test "clicking same column twice toggles order direction", %{conn: conn} do
      insert(:post, title: "Cherry", published: true)
      insert(:post, title: "Apple", published: true)
      insert(:post, title: "Banana", published: true)

      conn
      |> visit(~p"/admin/posts")
      |> unwrap(fn view ->
        view
        |> element("a", "Title")
        |> render_click()
      end)
      |> assert_has("table tbody tr:first-child td", text: "Apple")
      |> unwrap(fn view ->
        view
        |> element("a", "Title")
        |> render_click()
      end)
      |> assert_has("table tbody tr:first-child td", text: "Cherry")
      |> assert_has("table tbody tr:last-child td", text: "Apple")
    end
  end
end
