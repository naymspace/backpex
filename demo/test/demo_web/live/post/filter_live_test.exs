defmodule DemoWeb.Live.Post.FilterLiveTest do
  use DemoWeb.ConnCase, async: false

  import Demo.EctoFactory
  import Phoenix.LiveViewTest

  # The posts page has a default `published` filter with value `["published"]`.
  # When visiting `/admin/posts` without filter params, it redirects to add this default.

  describe "boolean filter" do
    test "default published filter shows only published posts", %{conn: conn} do
      insert(:post, title: "Published Post", published: true)
      insert(:post, title: "Draft Post", published: false)

      conn
      |> visit(~p"/admin/posts")
      |> assert_has("table tbody tr", count: 1)
      |> assert_has("td", text: "Published Post")
      |> refute_has("td", text: "Draft Post")
    end

    test "filtering for not_published shows only unpublished posts", %{conn: conn} do
      insert(:post, title: "Published Post", published: true)
      insert(:post, title: "Draft Post", published: false)

      params = %{"filters" => %{"published" => ["not_published"]}}

      conn
      |> visit(~p"/admin/posts?#{params}")
      |> assert_has("table tbody tr", count: 1)
      |> assert_has("td", text: "Draft Post")
      |> refute_has("td", text: "Published Post")
    end

    test "selecting both options shows all posts", %{conn: conn} do
      insert(:post, title: "Published Post", published: true)
      insert(:post, title: "Draft Post", published: false)

      params = %{"filters" => %{"published" => ["published", "not_published"]}}

      conn
      |> visit(~p"/admin/posts?#{params}")
      |> assert_has("table tbody tr", count: 2)
      |> assert_has("td", text: "Published Post")
      |> assert_has("td", text: "Draft Post")
    end

    test "toggling published filter via form change", %{conn: conn} do
      insert(:post, title: "Published Post", published: true)
      insert(:post, title: "Draft Post", published: false)

      conn
      |> visit(~p"/admin/posts")
      |> assert_has("table tbody tr", count: 1)
      |> unwrap(fn view ->
        view
        |> form("form[phx-change='change-filter']", filters: %{published: ["published", "not_published"]})
        |> render_change()
      end)
      |> assert_has("table tbody tr", count: 2)
      |> assert_has("td", text: "Published Post")
      |> assert_has("td", text: "Draft Post")
    end
  end

  describe "select filter" do
    test "filters posts by category", %{conn: conn} do
      category_a = insert(:category, name: "Technology")
      category_b = insert(:category, name: "Sports")
      insert(:post, title: "Tech Post", published: true, category: category_a)
      insert(:post, title: "Sports Post", published: true, category: category_b)

      params = %{"filters" => %{"published" => ["published"], "category_id" => category_a.id}}

      conn
      |> visit(~p"/admin/posts?#{params}")
      |> assert_has("table tbody tr", count: 1)
      |> assert_has("td", text: "Tech Post")
      |> refute_has("td", text: "Sports Post")
    end

    test "selecting a category via form change", %{conn: conn} do
      category_a = insert(:category, name: "Technology")
      category_b = insert(:category, name: "Sports")
      insert(:post, title: "Tech Post", published: true, category: category_a)
      insert(:post, title: "Sports Post", published: true, category: category_b)

      conn
      |> visit(~p"/admin/posts")
      |> assert_has("table tbody tr", count: 2)
      |> unwrap(fn view ->
        view
        |> form("form[phx-change='change-filter']", filters: %{category_id: category_a.id})
        |> render_change()
      end)
      |> assert_has("table tbody tr", count: 1)
      |> assert_has("td", text: "Tech Post")
      |> refute_has("td", text: "Sports Post")
    end
  end

  describe "multi-select filter" do
    test "filters posts by a single selected user", %{conn: conn} do
      user_a = insert(:user, first_name: "Alice", last_name: "Smith")
      user_b = insert(:user, first_name: "Bob", last_name: "Jones")
      insert(:post, title: "Alice Post", published: true, user: user_a)
      insert(:post, title: "Bob Post", published: true, user: user_b)

      params = %{"filters" => %{"published" => ["published"], "user_id" => [user_a.id]}}

      conn
      |> visit(~p"/admin/posts?#{params}")
      |> assert_has("table tbody tr", count: 1)
      |> assert_has("td", text: "Alice Post")
      |> refute_has("td", text: "Bob Post")
    end

    test "filters posts by multiple selected users", %{conn: conn} do
      user_a = insert(:user, first_name: "Alice", last_name: "Smith")
      user_b = insert(:user, first_name: "Bob", last_name: "Jones")
      user_c = insert(:user, first_name: "Carol", last_name: "Davis")
      insert(:post, title: "Alice Post", published: true, user: user_a)
      insert(:post, title: "Bob Post", published: true, user: user_b)
      insert(:post, title: "Carol Post", published: true, user: user_c)

      params = %{"filters" => %{"published" => ["published"], "user_id" => [user_a.id, user_b.id]}}

      conn
      |> visit(~p"/admin/posts?#{params}")
      |> assert_has("table tbody tr", count: 2)
      |> assert_has("td", text: "Alice Post")
      |> assert_has("td", text: "Bob Post")
      |> refute_has("td", text: "Carol Post")
    end

    test "selecting users via form change", %{conn: conn} do
      user_a = insert(:user, first_name: "Alice", last_name: "Smith")
      user_b = insert(:user, first_name: "Bob", last_name: "Jones")
      insert(:post, title: "Alice Post", published: true, user: user_a)
      insert(:post, title: "Bob Post", published: true, user: user_b)

      conn
      |> visit(~p"/admin/posts")
      |> assert_has("table tbody tr", count: 2)
      |> unwrap(fn view ->
        view
        |> form("form[phx-change='change-filter']", filters: %{user_id: [user_a.id]})
        |> render_change()
      end)
      |> assert_has("table tbody tr", count: 1)
      |> assert_has("td", text: "Alice Post")
      |> refute_has("td", text: "Bob Post")
    end
  end

  describe "range filter" do
    test "filters posts by likes range with start and end", %{conn: conn} do
      insert(:post, title: "Popular Post", published: true, likes: 200)
      insert(:post, title: "Average Post", published: true, likes: 50)
      insert(:post, title: "New Post", published: true, likes: 5)

      params = %{"filters" => %{"published" => ["published"], "likes" => %{"start" => "100", "end" => "300"}}}

      conn
      |> visit(~p"/admin/posts?#{params}")
      |> assert_has("table tbody tr", count: 1)
      |> assert_has("td", text: "Popular Post")
      |> refute_has("td", text: "Average Post")
      |> refute_has("td", text: "New Post")
    end

    test "filters with only start value via form change", %{conn: conn} do
      insert(:post, title: "Popular Post", published: true, likes: 200)
      insert(:post, title: "New Post", published: true, likes: 5)

      conn
      |> visit(~p"/admin/posts")
      |> assert_has("table tbody tr", count: 2)
      |> unwrap(fn view ->
        view
        |> form("form[phx-change='change-filter']", filters: %{likes: %{start: "100"}})
        |> render_change()
      end)
      |> assert_has("table tbody tr", count: 1)
      |> assert_has("td", text: "Popular Post")
      |> refute_has("td", text: "New Post")
    end

    test "filters with only end value via form change", %{conn: conn} do
      insert(:post, title: "Popular Post", published: true, likes: 200)
      insert(:post, title: "New Post", published: true, likes: 5)

      conn
      |> visit(~p"/admin/posts")
      |> assert_has("table tbody tr", count: 2)
      |> unwrap(fn view ->
        view
        |> form("form[phx-change='change-filter']", filters: %{likes: %{end: "100"}})
        |> render_change()
      end)
      |> assert_has("table tbody tr", count: 1)
      |> refute_has("td", text: "Popular Post")
      |> assert_has("td", text: "New Post")
    end
  end

  describe "filter presets" do
    test "likes 'Over 100' preset filters correctly", %{conn: conn} do
      insert(:post, title: "Popular Post", published: true, likes: 200)
      insert(:post, title: "New Post", published: true, likes: 5)

      conn
      |> visit(~p"/admin/posts")
      |> assert_has("table tbody tr", count: 2)
      |> unwrap(fn view ->
        view
        |> element("div[phx-click='filter-preset-selected'][phx-value-field='likes'][phx-value-preset-index='0']")
        |> render_click()
      end)
      |> assert_has("table tbody tr", count: 1)
      |> assert_has("td", text: "Popular Post")
      |> refute_has("td", text: "New Post")
    end

    test "likes '1-99' preset filters correctly", %{conn: conn} do
      insert(:post, title: "Popular Post", published: true, likes: 200)
      insert(:post, title: "Average Post", published: true, likes: 50)
      insert(:post, title: "Zero Post", published: true, likes: 0)

      conn
      |> visit(~p"/admin/posts")
      |> assert_has("table tbody tr", count: 3)
      |> unwrap(fn view ->
        view
        |> element("div[phx-click='filter-preset-selected'][phx-value-field='likes'][phx-value-preset-index='1']")
        |> render_click()
      end)
      |> assert_has("table tbody tr", count: 1)
      |> assert_has("td", text: "Average Post")
      |> refute_has("td", text: "Popular Post")
      |> refute_has("td", text: "Zero Post")
    end
  end

  describe "clear filter" do
    test "clearing category filter shows all published posts", %{conn: conn} do
      category_a = insert(:category, name: "Technology")
      category_b = insert(:category, name: "Sports")
      insert(:post, title: "Tech Post", published: true, category: category_a)
      insert(:post, title: "Sports Post", published: true, category: category_b)

      params = %{"filters" => %{"published" => ["published"], "category_id" => category_a.id}}

      conn
      |> visit(~p"/admin/posts?#{params}")
      |> assert_has("table tbody tr", count: 1)
      |> assert_has("td", text: "Tech Post")
      |> unwrap(fn view ->
        view
        |> element("button[phx-click='clear-filter'][phx-value-field='category_id'][aria-label]")
        |> render_click()
      end)
      |> assert_has("table tbody tr", count: 2)
      |> assert_has("td", text: "Tech Post")
      |> assert_has("td", text: "Sports Post")
    end

    test "clearing likes filter shows all published posts", %{conn: conn} do
      insert(:post, title: "Popular Post", published: true, likes: 200)
      insert(:post, title: "New Post", published: true, likes: 5)

      params = %{"filters" => %{"published" => ["published"], "likes" => %{"start" => "100", "end" => "300"}}}

      conn
      |> visit(~p"/admin/posts?#{params}")
      |> assert_has("table tbody tr", count: 1)
      |> unwrap(fn view ->
        view
        |> element("button[phx-click='clear-filter'][phx-value-field='likes'][aria-label]")
        |> render_click()
      end)
      |> assert_has("table tbody tr", count: 2)
    end
  end

  describe "multiple filters combined" do
    test "combines category and likes range filters", %{conn: conn} do
      category = insert(:category, name: "Technology")
      other_category = insert(:category, name: "Sports")
      insert(:post, title: "Popular Tech", published: true, likes: 200, category: category)
      insert(:post, title: "New Tech", published: true, likes: 5, category: category)
      insert(:post, title: "Popular Sports", published: true, likes: 200, category: other_category)

      params = %{
        "filters" => %{
          "published" => ["published"],
          "category_id" => category.id,
          "likes" => %{"start" => "100", "end" => ""}
        }
      }

      conn
      |> visit(~p"/admin/posts?#{params}")
      |> assert_has("table tbody tr", count: 1)
      |> assert_has("td", text: "Popular Tech")
      |> refute_has("td", text: "New Tech")
      |> refute_has("td", text: "Popular Sports")
    end

    test "adding a range filter to an existing category filter", %{conn: conn} do
      category = insert(:category, name: "Technology")
      insert(:post, title: "Popular Tech", published: true, likes: 200, category: category)
      insert(:post, title: "New Tech", published: true, likes: 5, category: category)

      params = %{"filters" => %{"published" => ["published"], "category_id" => category.id}}

      conn
      |> visit(~p"/admin/posts?#{params}")
      |> assert_has("table tbody tr", count: 2)
      |> unwrap(fn view ->
        view
        |> form("form[phx-change='change-filter']", filters: %{likes: %{start: "100"}})
        |> render_change()
      end)
      |> assert_has("table tbody tr", count: 1)
      |> assert_has("td", text: "Popular Tech")
      |> refute_has("td", text: "New Tech")
    end
  end

  describe "filter validation" do
    test "invalid start value in range filter does not apply filter", %{conn: conn} do
      insert(:post, title: "Post A", published: true, likes: 200)
      insert(:post, title: "Post B", published: true, likes: 5)

      params = %{"filters" => %{"published" => ["published"], "likes" => %{"start" => "abc", "end" => ""}}}

      conn
      |> visit(~p"/admin/posts?#{params}")
      |> assert_has("table tbody tr", count: 2)
      |> assert_has("td", text: "Post A")
      |> assert_has("td", text: "Post B")
    end

    test "invalid category value does not apply filter", %{conn: conn} do
      insert(:post, title: "Tech Post", published: true)
      insert(:post, title: "Other Post", published: true)

      params = %{"filters" => %{"published" => ["published"], "category_id" => "invalid-uuid"}}

      conn
      |> visit(~p"/admin/posts?#{params}")
      |> assert_has("table tbody tr", count: 2)
      |> assert_has("td", text: "Tech Post")
      |> assert_has("td", text: "Other Post")
    end
  end

  describe "filter badges" do
    test "shows badge for active category filter", %{conn: conn} do
      category = insert(:category, name: "Technology")
      insert(:post, published: true, category: category)

      params = %{"filters" => %{"published" => ["published"], "category_id" => category.id}}

      conn
      |> visit(~p"/admin/posts?#{params}")
      |> assert_has("button[aria-label='Clear Category filter']")
    end

    test "shows badge for active likes filter", %{conn: conn} do
      insert(:post, published: true, likes: 200)

      params = %{"filters" => %{"published" => ["published"], "likes" => %{"start" => "100", "end" => "300"}}}

      conn
      |> visit(~p"/admin/posts?#{params}")
      |> assert_has("button[aria-label='Clear Likes filter']")
    end

    test "shows badge for default published filter", %{conn: conn} do
      insert(:post, published: true)

      conn
      |> visit(~p"/admin/posts")
      |> assert_has("button[aria-label='Clear Published? filter']")
    end
  end
end
