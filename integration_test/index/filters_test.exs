defmodule Backpex.Integration.Index.FiltersTest do
  use Backpex.ConnCase, async: true

  # Posts have a `published` filter with the default `["published"]`. Visiting `/admin/posts` without filter params
  # redirects to the URL with this default. The likes and created at range filters both label their inputs "From" and
  # "To", so the likes inputs are targeted by name.

  describe "boolean filter" do
    setup do
      insert(:post, title: "Published Post", published: true)
      insert(:post, title: "Draft Post", published: false)
      :ok
    end

    test "applies its default", %{conn: conn} do
      conn
      |> visit(~p"/admin/posts")
      |> assert_has("table tbody tr", count: 1)
      |> assert_has("td", text: "Published Post")
      |> refute_has("td", text: "Draft Post")
    end

    test "filters by an option from the URL", %{conn: conn} do
      conn
      |> visit(~p"/admin/posts?#{%{"filters" => %{"published" => ["not_published"]}}}")
      |> assert_has("table tbody tr", count: 1)
      |> assert_has("td", text: "Draft Post")
      |> refute_has("td", text: "Published Post")
    end

    test "combines the selected options with or", %{conn: conn} do
      conn
      |> visit(~p"/admin/posts?#{%{"filters" => %{"published" => ["published", "not_published"]}}}")
      |> assert_has("table tbody tr", count: 2)
      |> assert_has("td", text: "Published Post")
      |> assert_has("td", text: "Draft Post")
    end

    test "filters by the options selected in the form", %{conn: conn} do
      conn
      |> visit(~p"/admin/posts")
      |> assert_has("table tbody tr", count: 1)
      |> check("Not published")
      |> assert_has("table tbody tr", count: 2)
      |> assert_has("td", text: "Published Post")
      |> assert_has("td", text: "Draft Post")
    end
  end

  describe "select filter" do
    setup do
      category = insert(:category, name: "Technology")
      insert(:post, title: "Tech Post", category: category)
      insert(:post, title: "Sports Post", category: build(:category, name: "Sports"))
      %{category: category}
    end

    test "filters by the option from the URL", %{conn: conn, category: category} do
      conn
      |> visit(~p"/admin/posts?#{%{"filters" => %{"published" => ["published"], "category_id" => category.id}}}")
      |> assert_has("table tbody tr", count: 1)
      |> assert_has("td", text: "Tech Post")
      |> refute_has("td", text: "Sports Post")
    end

    test "filters by the option selected in the form", %{conn: conn, category: category} do
      conn
      |> visit(~p"/admin/posts")
      |> assert_has("table tbody tr", count: 2)
      |> select("Select category ...", option: category.name)
      |> assert_has("table tbody tr", count: 1)
      |> assert_has("td", text: "Tech Post")
      |> refute_has("td", text: "Sports Post")
    end
  end

  describe "multi select filter" do
    setup do
      users = [
        insert(:user, first_name: "Alice", last_name: "Smith"),
        insert(:user, first_name: "Bob", last_name: "Jones"),
        insert(:user, first_name: "Carol", last_name: "Davis")
      ]

      for user <- users, do: insert(:post, title: "#{user.first_name} Post", user: user)

      %{users: users}
    end

    test "filters by a single option from the URL", %{conn: conn, users: [alice | _users]} do
      conn
      |> visit(~p"/admin/posts?#{%{"filters" => %{"published" => ["published"], "user_id" => [alice.id]}}}")
      |> assert_has("table tbody tr", count: 1)
      |> assert_has("td", text: "Alice Post")
      |> refute_has("td", text: "Bob Post")
    end

    test "filters by several options from the URL", %{conn: conn, users: [alice, bob, _carol]} do
      conn
      |> visit(~p"/admin/posts?#{%{"filters" => %{"published" => ["published"], "user_id" => [alice.id, bob.id]}}}")
      |> assert_has("table tbody tr", count: 2)
      |> assert_has("td", text: "Alice Post")
      |> assert_has("td", text: "Bob Post")
      |> refute_has("td", text: "Carol Post")
    end

    test "filters by the options selected in the form", %{conn: conn, users: [alice | _users]} do
      conn
      |> visit(~p"/admin/posts")
      |> assert_has("table tbody tr", count: 3)
      |> check("#{alice.first_name} #{alice.last_name}")
      |> assert_has("table tbody tr", count: 1)
      |> assert_has("td", text: "Alice Post")
      |> refute_has("td", text: "Bob Post")
    end
  end

  describe "range filter" do
    setup do
      insert(:post, title: "Popular Post", likes: 200)
      insert(:post, title: "Average Post", likes: 50)
      insert(:post, title: "New Post", likes: 5)
      :ok
    end

    test "filters by start and end from the URL", %{conn: conn} do
      params = %{"filters" => %{"published" => ["published"], "likes" => %{"start" => "100", "end" => "300"}}}

      conn
      |> visit(~p"/admin/posts?#{params}")
      |> assert_has("table tbody tr", count: 1)
      |> assert_has("td", text: "Popular Post")
      |> refute_has("td", text: "Average Post")
      |> refute_has("td", text: "New Post")
    end

    test "filters by a start value only", %{conn: conn} do
      conn
      |> visit(~p"/admin/posts")
      |> assert_has("table tbody tr", count: 3)
      |> fill_in("input[name='filters[likes][start]']", "From", with: "100")
      |> assert_has("table tbody tr", count: 1)
      |> assert_has("td", text: "Popular Post")
      |> refute_has("td", text: "New Post")
    end

    test "filters by an end value only", %{conn: conn} do
      conn
      |> visit(~p"/admin/posts")
      |> assert_has("table tbody tr", count: 3)
      |> fill_in("input[name='filters[likes][end]']", "To", with: "100")
      |> assert_has("table tbody tr", count: 2)
      |> refute_has("td", text: "Popular Post")
      |> assert_has("td", text: "Average Post")
      |> assert_has("td", text: "New Post")
    end
  end

  describe "filter presets" do
    setup do
      insert(:post, title: "Popular Post", likes: 200)
      insert(:post, title: "Average Post", likes: 50)
      insert(:post, title: "Zero Post", likes: 0)
      :ok
    end

    test "apply the values of the selected preset", %{conn: conn} do
      conn
      |> visit(~p"/admin/posts")
      |> assert_has("table tbody tr", count: 3)
      |> click_button("Over 100")
      |> assert_has("table tbody tr", count: 1)
      |> assert_has("td", text: "Popular Post")

      conn
      |> visit(~p"/admin/posts")
      |> click_button("1-99")
      |> assert_has("table tbody tr", count: 1)
      |> assert_has("td", text: "Average Post")
      |> refute_has("td", text: "Popular Post")
      |> refute_has("td", text: "Zero Post")
    end
  end

  describe "clearing a filter" do
    test "shows the items the select filter hid", %{conn: conn} do
      category = insert(:category, name: "Technology")
      insert(:post, title: "Tech Post", category: category)
      insert(:post, title: "Sports Post", category: build(:category, name: "Sports"))

      conn
      |> visit(~p"/admin/posts?#{%{"filters" => %{"published" => ["published"], "category_id" => category.id}}}")
      |> assert_has("table tbody tr", count: 1)
      |> assert_has("td", text: "Tech Post")
      |> click_button("Clear Category filter")
      |> assert_has("table tbody tr", count: 2)
      |> assert_has("td", text: "Tech Post")
      |> assert_has("td", text: "Sports Post")
    end

    test "shows the items the range filter hid", %{conn: conn} do
      insert(:post, title: "Popular Post", likes: 200)
      insert(:post, title: "New Post", likes: 5)

      params = %{"filters" => %{"published" => ["published"], "likes" => %{"start" => "100", "end" => "300"}}}

      conn
      |> visit(~p"/admin/posts?#{params}")
      |> assert_has("table tbody tr", count: 1)
      |> click_button("Clear Likes filter")
      |> assert_has("table tbody tr", count: 2)
    end
  end

  describe "several filters" do
    setup do
      category = insert(:category, name: "Technology")
      insert(:post, title: "Popular Tech", likes: 200, category: category)
      insert(:post, title: "New Tech", likes: 5, category: category)
      insert(:post, title: "Popular Sports", likes: 200, category: build(:category, name: "Sports"))
      %{category: category}
    end

    test "are combined with and", %{conn: conn, category: category} do
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

    test "keep the active filters when another filter is changed", %{conn: conn, category: category} do
      conn
      |> visit(~p"/admin/posts?#{%{"filters" => %{"published" => ["published"], "category_id" => category.id}}}")
      |> assert_has("table tbody tr", count: 2)
      |> fill_in("input[name='filters[likes][start]']", "From", with: "100")
      |> assert_has("table tbody tr", count: 1)
      |> assert_has("td", text: "Popular Tech")
      |> refute_has("td", text: "New Tech")
    end
  end

  describe "invalid filter values" do
    setup do
      insert(:post, title: "Post A", likes: 200)
      insert(:post, title: "Post B", likes: 5)
      :ok
    end

    test "do not apply a range filter with a start value that is not a number", %{conn: conn} do
      params = %{"filters" => %{"published" => ["published"], "likes" => %{"start" => "abc", "end" => ""}}}

      conn
      |> visit(~p"/admin/posts?#{params}")
      |> assert_has("table tbody tr", count: 2)
      |> assert_has("td", text: "Post A")
      |> assert_has("td", text: "Post B")
    end

    test "do not apply a range filter with a decimal start value on an integer field", %{conn: conn} do
      params = %{"filters" => %{"published" => ["published"], "likes" => %{"start" => "1.5", "end" => ""}}}

      conn
      |> visit(~p"/admin/posts?#{params}")
      |> assert_has("table tbody tr", count: 2)
      |> assert_has("#filter-form", text: "has invalid start value")
    end

    test "show an error for a decimal end value on an integer field entered in the form", %{conn: conn} do
      conn
      |> visit(~p"/admin/posts")
      |> assert_has("table tbody tr", count: 2)
      |> fill_in("input[name='filters[likes][end]']", "To", with: "99.5")
      |> assert_has("table tbody tr", count: 2)
      |> assert_has("#filter-form", text: "has invalid end value")
    end

    test "do not apply a select filter with an unknown option", %{conn: conn} do
      params = %{"filters" => %{"published" => ["published"], "category_id" => "invalid-uuid"}}

      conn
      |> visit(~p"/admin/posts?#{params}")
      |> assert_has("table tbody tr", count: 2)
      |> assert_has("td", text: "Post A")
      |> assert_has("td", text: "Post B")
    end
  end

  describe "confirmed item actions" do
    test "keep a cleared default filter cleared", %{conn: conn} do
      # Posts without tags, so the posts_tags foreign key does not prevent the delete.
      insert(:post, title: "Published Post", published: true, tags: [])
      draft_to_keep = insert(:post, title: "Draft to Keep", published: false, tags: [])
      draft_to_delete = insert(:post, title: "Draft to Delete", published: false, tags: [])

      conn
      |> visit(~p"/admin/posts")
      |> assert_has("table tbody tr", count: 1)
      |> refute_has("td", text: "Draft to Keep")
      |> click_button("Clear Published? filter")
      |> assert_has("table tbody tr", count: 3)
      |> within("#row-item-#{draft_to_delete.id}", &click_button(&1, "Delete"))
      |> within("#resource-form", &click_button(&1, "Delete"))
      # The confirmed delete navigates to `return_to`, which remounts the index. Without `filters_changed` in that URL
      # the index would apply the default filter again and hide the remaining draft.
      |> assert_path(~p"/admin/posts",
        query_params: %{
          "filters_changed" => "true",
          "order_by" => "id",
          "order_direction" => "asc",
          "per_page" => "15",
          "page" => "1"
        }
      )
      |> assert_has("td", text: "Published Post")
      |> assert_has("td", text: draft_to_keep.title)
      |> refute_has("td", text: draft_to_delete.title)
    end
  end

  describe "filter badges" do
    test "are shown for active filters, including the default", %{conn: conn} do
      category = insert(:category, name: "Technology")
      insert(:post, likes: 200, category: category)

      conn
      |> visit(~p"/admin/posts")
      |> assert_has("button[aria-label='Clear Published? filter']")

      params = %{
        "filters" => %{
          "published" => ["published"],
          "category_id" => category.id,
          "likes" => %{"start" => "100", "end" => "300"}
        }
      }

      conn
      |> visit(~p"/admin/posts?#{params}")
      |> assert_has("button[aria-label='Clear Category filter']")
      |> assert_has("button[aria-label='Clear Likes filter']")
    end

    test "are not shown for inactive filters", %{conn: conn} do
      insert(:product, quantity: 100)

      conn
      |> visit(~p"/admin/products")
      |> refute_has("button[aria-label='Clear QTY filter']")
    end
  end
end
