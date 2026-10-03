defmodule DemoWeb.Live.Post.IndexEditLiveTest do
  use DemoWeb.ConnCase, async: false

  import Demo.EctoFactory
  import Ecto.Query
  import Phoenix.LiveViewTest

  describe "author index form" do
    test "lists all authors as options of every row", %{conn: conn} do
      posts = insert_list(3, :post, published: true)
      deleted_user = insert(:user, deleted_at: DateTime.utc_now(:second))

      {:ok, view, _html} = live(conn, index_path(conn))

      author_ids = posts |> Enum.map(&to_string(&1.user_id)) |> Enum.sort()

      for post <- posts do
        options = author_options(view, post)

        assert Enum.sort(options) == author_ids
        refute to_string(deleted_user.id) in options
      end
    end

    test "loads the options of all rows with the same number of queries", %{conn: conn} do
      insert_list(2, :post, published: true)
      path = index_path(conn)
      few_rows_queries = count_users_queries(fn -> assert_rendered_rows(conn, path, 2) end)

      insert_list(6, :post, published: true)
      many_rows_queries = count_users_queries(fn -> assert_rendered_rows(conn, path, 8) end)

      assert many_rows_queries == few_rows_queries
    end

    test "passes the item of each row to the options query" do
      [post, other_post] = insert_list(2, :post, published: true)

      field_options = %{
        module: Backpex.Fields.BelongsTo,
        label: "Author",
        display_field: :username,
        index_editable: true,
        options_query: fn query, assigns -> where(query, [user], user.id == ^assigns.item.user_id) end
      }

      assigns = %{live_resource: DemoWeb.PostLive, live_action: :index}

      assert %{index_form_options: options} =
               Backpex.Fields.BelongsTo.index_assigns({:user, field_options}, [post, other_post], assigns)

      assert options[post.id] == [{post.user.username, post.user_id}]
      assert options[other_post.id] == [{other_post.user.username, other_post.user_id}]
    end

    test "does not load the options again when rendering without item changes", %{conn: conn} do
      insert_list(3, :post, published: true)
      {:ok, view, _html} = live(conn, index_path(conn))

      assert count_users_queries(fn -> render_click(view, "toggle-item-selection") end) == 0
    end
  end

  describe "inline edit" do
    test "saves the change and shows the updated item", %{conn: conn} do
      post = insert(:post, published: true)
      other_user = insert(:user)
      {:ok, view, _html} = live(conn, index_path(conn))

      view
      |> form("#index-form-user-#{post.id}", index_form: %{value: other_user.id})
      |> render_change()

      assert Demo.Repo.get!(Demo.Post, post.id).user_id == other_user.id
      assert view |> element("#index-form-user-#{post.id} option[selected]") |> render() =~ ~s(value="#{other_user.id}")
    end
  end

  defp index_path(conn) do
    case live(conn, ~p"/admin/posts") do
      {:error, {:live_redirect, %{to: to}}} -> to
      {:ok, _view, _html} -> ~p"/admin/posts"
    end
  end

  defp assert_rendered_rows(conn, path, count) do
    {:ok, view, _html} = live(conn, path)

    assert view
           |> render()
           |> LazyHTML.from_fragment()
           |> LazyHTML.query("form[id^='index-form-user-']")
           |> Enum.count() ==
             count
  end

  defp author_options(view, post) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#index-form-user-#{post.id} option")
    |> LazyHTML.attribute("value")
    |> Enum.reject(&(&1 == ""))
  end

  defp count_users_queries(fun) do
    ref = make_ref()
    handler_id = {__MODULE__, ref}
    :telemetry.attach(handler_id, [:demo, :repo, :query], &__MODULE__.handle_query/4, {self(), ref})

    try do
      fun.()
    after
      :telemetry.detach(handler_id)
    end

    receive_users_queries(ref, 0)
  end

  @doc false
  def handle_query(_event, _measurements, %{source: "users"}, {test_pid, ref}) do
    if self() == test_pid or test_pid in Process.get(:"$callers", []), do: send(test_pid, {ref, :query})
  end

  def handle_query(_event, _measurements, _metadata, _config), do: :ok

  defp receive_users_queries(ref, count) do
    receive do
      {^ref, :query} -> receive_users_queries(ref, count + 1)
    after
      0 -> count
    end
  end
end
