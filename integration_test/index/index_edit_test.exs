defmodule Backpex.Integration.Index.IndexEditTest do
  # The query counts include the reloads of the LiveViews under test. These also reload on the PubSub events of other
  # tests that change posts, so the tests must not run concurrently with them.
  use Backpex.ConnCase, async: false

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias Backpex.Fields.BelongsTo
  alias Backpex.Test.Post
  alias Backpex.Test.Product
  alias Backpex.Test.Sample
  alias Backpex.Test.User

  @category_id "0b3a5c1e-6d0f-4a52-9a3b-1f2e3d4c5b6a"
  @other_category_id "7c9e2f4a-1b3d-4e5f-8a6b-9c0d1e2f3a4b"
  @unknown_category_id "f1e2d3c4-b5a6-4978-8695-a4b3c2d1e0f9"

  # One row for every field that implements `c:Backpex.Field.render_index_form/1`, all index editable in
  # `Backpex.Test.IndexEditSampleLive`:
  #
  #   * `field` - the name of the field, `column` - the column it is stored in, if that differs
  #   * `initial` - the stored value before the edit
  #   * `send` - the valid value as the browser sends it, `stored` - that value in the database
  #   * `rendered` - what the input of the row matches after the edit was saved
  #   * `invalid` - a value that must not be saved, `error_class` - the class that marks the input as invalid
  @index_edit_matrix [
    %{
      module: Backpex.Fields.Text,
      field: :text,
      initial: "Before",
      send: "After",
      stored: "After",
      rendered: "[value='After']",
      invalid: "",
      error_class: "input-error"
    },
    %{
      module: Backpex.Fields.Number,
      field: :number,
      initial: 1,
      send: "42",
      stored: 42,
      rendered: "[value='42']",
      invalid: "forty-two",
      error_class: "input-error"
    },
    %{
      module: Backpex.Fields.Boolean,
      field: :boolean,
      initial: false,
      send: "true",
      stored: true,
      rendered: "[checked]",
      invalid: "maybe",
      error_class: "toggle-error"
    },
    %{
      module: Backpex.Fields.Select,
      field: :select,
      initial: :one,
      send: "two",
      stored: :two,
      rendered: " option[selected][value='two']",
      invalid: "four",
      error_class: "select-error"
    },
    %{
      module: Backpex.Fields.Date,
      field: :date,
      initial: ~D[2026-01-02],
      send: "2026-03-04",
      stored: ~D[2026-03-04],
      rendered: "[value='2026-03-04']",
      invalid: "2026-02-30",
      error_class: "input-error"
    },
    %{
      module: Backpex.Fields.DateTime,
      field: :date_time,
      initial: ~U[2026-01-02 10:00:00Z],
      send: "2026-03-04T05:06",
      stored: ~U[2026-03-04 05:06:00Z],
      rendered: "[value='2026-03-04T05:06']",
      invalid: "2026-02-30T05:06",
      error_class: "input-error"
    },
    %{
      module: Backpex.Fields.Time,
      field: :time,
      initial: ~T[10:00:00],
      send: "05:06",
      stored: ~T[05:06:00],
      rendered: "[value='05:06:00']",
      invalid: "25:06",
      error_class: "input-error"
    },
    %{
      module: Backpex.Fields.Email,
      field: :email,
      initial: "before@example.com",
      send: "after@example.com",
      stored: "after@example.com",
      rendered: "[value='after@example.com']",
      invalid: "no-at-sign",
      error_class: "input-error"
    },
    %{
      module: BelongsTo,
      field: :category,
      column: :category_id,
      initial: @category_id,
      send: @other_category_id,
      stored: @other_category_id,
      rendered: " option[selected][value='#{@other_category_id}']",
      invalid: @unknown_category_id,
      error_class: "select-error"
    }
  ]

  describe "index editable fields" do
    setup %{conn: conn} do
      insert(:category, id: @category_id)
      insert(:category, id: @other_category_id)

      initial = Map.new(@index_edit_matrix, &{Map.get(&1, :column, &1.field), &1.initial})
      sample = insert(:sample, initial)
      {:ok, view, _html} = live(conn, ~p"/admin/index-edit-samples")

      %{sample: sample, view: view}
    end

    test "the matrix covers every field that implements render_index_form/1" do
      {:ok, modules} = :application.get_key(:backpex, :modules)

      index_editable =
        for module <- modules,
            match?(["Backpex", "Fields", _name], Module.split(module)),
            Code.ensure_loaded?(module),
            function_exported?(module, :render_index_form, 1),
            do: module

      covered = Enum.map(@index_edit_matrix, & &1.module)

      assert Enum.sort(index_editable) == Enum.sort(covered), """
      The fields that implement render_index_form/1 and the rows of @index_edit_matrix differ.

      Without a row: #{inspect(index_editable -- covered)}
      Row without render_index_form/1: #{inspect(covered -- index_editable)}

      Add a field of the new type with `index_editable: true` to Backpex.Test.IndexEditSampleLive and a row to
      @index_edit_matrix.
      """
    end

    for row <- @index_edit_matrix do
      @tag row: row
      test "#{inspect(row.module)} saves a change and shows the updated value", %{row: row, sample: sample, view: view} do
        input = "#index-form-input-#{row.field}-#{sample.id}"

        assert has_element?(view, input)
        refute has_element?(view, input <> row.rendered)

        send_index_edit(view, row.field, sample, row.send)

        assert stored_value(sample, row) == row.stored
        assert has_element?(view, input <> row.rendered)
        refute has_element?(view, "#{input}.#{row.error_class}")
      end

      @tag row: row
      test "#{inspect(row.module)} marks an invalid change that is not saved", %{row: row, sample: sample, view: view} do
        input = "#index-form-input-#{row.field}-#{sample.id}"

        refute has_element?(view, "#{input}.#{row.error_class}")

        send_index_edit(view, row.field, sample, row.invalid)

        assert stored_value(sample, row) == row.initial
        assert has_element?(view, "#{input}.#{row.error_class}")
      end
    end
  end

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

      # Without queries the counts would be equal, too.
      assert few_rows_queries > 0
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
      [post | _posts] = insert_list(3, :post)
      {:ok, view, _html} = live(conn, index_path(conn))

      assert count_queries("users", fn -> render_click(view, "toggle-item-selection") end) == 0

      # An item change loads the options again, so the count above would see these queries.
      assert count_queries("users", fn ->
               send(view.pid, {"backpex:updated", post})
               render(view)
             end) > 0
    end

    test "does not load the options again when an item of another page changes", %{conn: conn} do
      # A page holds 15 posts.
      posts = insert_list(16, :post)
      {:ok, view, _html} = live(conn, index_path(conn))
      [off_page_post] = Enum.reject(posts, &has_element?(view, "#index-form-user-#{&1.id}"))

      assert count_queries("users", fn ->
               send(view.pid, {"backpex:updated", off_page_post})
               render(view)
             end) == 0
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

  # The featured short link of `Backpex.Test.ProductShortLinksLive` is an index editable BelongsTo field of
  # `Backpex.Test.ShortLink`, whose key is `short_key`.
  describe "index editable belongs to field of a related schema whose key is not id" do
    setup do
      link = insert(:short_link, short_key: "docs", url: "https://docs.example.com/")
      insert(:short_link, short_key: "blog", url: "https://blog.example.com/")

      %{product: insert(:product, featured_short_link: link)}
    end

    test "renders the keys as option values, saves the change and shows the updated item", context do
      %{conn: conn, product: product} = context
      form = "#index-form-featured_short_link-#{product.id}"

      session =
        conn
        |> visit(~p"/admin/product-short-links")
        |> assert_has("#{form} option[selected][value='docs']")
        |> select("#index-form-input-featured_short_link-#{product.id}", "Featured Short Link",
          option: "https://blog.example.com/"
        )

      assert Repo.get!(Product, product.id).featured_short_link_key == "blog"

      session
      |> assert_has("#{form} option[selected]", count: 1)
      |> assert_has("#{form} option[selected][value='blog']")
    end

    test "saves an option and refuses a value that is not an option" do
      field_options = %{
        module: BelongsTo,
        label: "Featured Short Link",
        display_field: :url,
        options_query: fn query, _assigns -> where(query, [link], link.short_key != "docs") end
      }

      field = {:featured_short_link, field_options}
      assigns = %{live_resource: Backpex.Test.ProductShortLinksLive, field_options: field_options}

      assert BelongsTo.index_editable_change(field, "blog", assigns) == %{featured_short_link_key: "blog"}
      assert BelongsTo.index_editable_change(field, "docs", assigns) == :error
      assert BelongsTo.index_editable_change(field, "unknown", assigns) == :error
    end
  end

  # Changes the index form of a field like the browser does: the event carries the hidden inputs of the form and the
  # value. The value is not checked against the input, as a client can send any value.
  defp send_index_edit(view, field, item, value) do
    view
    |> element("#index-form-#{field}-#{item.id}")
    |> render_change(%{"index_form" => %{"value" => value}})
  end

  defp stored_value(sample, row), do: Sample |> Repo.get!(sample.id) |> Map.fetch!(Map.get(row, :column, row.field))

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
