defmodule Backpex.Integration.Index.IndexEditTest do
  # The query counts include the reloads of the LiveViews under test. These also reload on the PubSub events of other
  # tests that change posts, so the tests must not run concurrently with them.
  use Backpex.ConnCase, async: false

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias Backpex.Fields.BelongsTo
  alias Backpex.Test.Post
  alias Backpex.Test.User

  describe "index editable text field" do
    test "marks an invalid change that is not saved", %{conn: conn} do
      user = insert(:user, username: "testuser123")

      session =
        conn
        |> visit(~p"/admin/users")
        |> fill_in("#index-form-input-username-#{user.id}", "Username", with: "")

      assert Repo.get!(User, user.id).username == "testuser123"
      assert_has(session, "#index-form-input-username-#{user.id}.input-error")
    end
  end

  # The author of a post is an index editable BelongsTo field with an `options_query` that excludes deleted users.
  describe "index editable belongs to field" do
    test "lists the options of the options_query in every row", %{conn: conn} do
      posts = insert_list(3, :post)
      deleted_user = insert(:user, deleted_at: DateTime.utc_now(:second))

      session = visit(conn, ~p"/admin/posts")

      for post <- posts do
        options = "#index-form-user-#{post.id} option:not([value=''])"

        session
        |> assert_has(options, count: length(posts))
        |> refute_has("#{options}[value='#{deleted_user.id}']")

        for author <- posts, do: assert_has(session, "#{options}[value='#{author.user_id}']")
      end
    end

    test "loads the options of all rows with the same number of queries", %{conn: conn} do
      insert_list(2, :post)
      path = index_path(conn)
      few_rows_queries = count_queries("users", fn -> assert_rendered_rows(conn, path, 2) end)

      insert_list(6, :post)
      many_rows_queries = count_queries("users", fn -> assert_rendered_rows(conn, path, 8) end)

      assert many_rows_queries == few_rows_queries
    end

    test "passes the item of each row to the options_query" do
      [post, other_post] = insert_list(2, :post)

      field_options = %{
        module: BelongsTo,
        label: "Author",
        display_field: :username,
        index_editable: true,
        options_query: fn query, assigns -> where(query, [user], user.id == ^assigns.item.user_id) end
      }

      assigns = %{live_resource: Backpex.Test.PostLive, live_action: :index}

      assert %{index_form_options: options} =
               BelongsTo.index_assigns({:user, field_options}, [post, other_post], assigns)

      assert options[post.id] == [{post.user.username, post.user_id}]
      assert options[other_post.id] == [{other_post.user.username, other_post.user_id}]
    end

    test "does not load the options again when rendering without item changes", %{conn: conn} do
      insert_list(3, :post)
      {:ok, view, _html} = live(conn, index_path(conn))

      assert count_queries("users", fn -> render_click(view, "toggle-item-selection") end) == 0
    end

    test "saves the change and shows the updated item", %{conn: conn} do
      post = insert(:post)
      other_user = insert(:user)

      session =
        conn
        |> visit(~p"/admin/posts")
        |> select("#index-form-input-user-#{post.id}", "Author",
          option: "#{other_user.first_name} #{other_user.last_name}"
        )

      assert Repo.get!(Post, post.id).user_id == other_user.id

      session
      |> assert_has("#index-form-user-#{post.id} option[selected]", count: 1)
      |> assert_has("#index-form-user-#{post.id} option[selected][value='#{other_user.id}']")
    end
  end

  # The posts index redirects to the URL with its default filter.
  defp index_path(conn) do
    {:error, {:live_redirect, %{to: to}}} = live(conn, ~p"/admin/posts")
    to
  end

  defp assert_rendered_rows(conn, path, count) do
    {:ok, view, _html} = live(conn, path)

    assert view
           |> render()
           |> LazyHTML.from_fragment()
           |> LazyHTML.query("form[id^='index-form-user-']")
           |> Enum.count() == count
  end
end
