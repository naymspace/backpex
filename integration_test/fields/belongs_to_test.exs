defmodule Backpex.Integration.Fields.BelongsToTest do
  use Backpex.ConnCase, async: true

  import Ecto.Query

  import Phoenix.LiveViewTest,
    only: [
      element: 2,
      element: 3,
      form: 2,
      put_submitter: 2,
      render_change: 2,
      render_click: 1,
      render_hook: 3,
      render_submit: 2
    ]

  alias Backpex.Fields.BelongsTo
  alias Backpex.Test.Post
  alias Backpex.Test.PostLive
  alias Backpex.Test.PostRelationOptionsLive
  alias Backpex.Test.Product
  alias Phoenix.HTML.Form
  alias Phoenix.LiveView.Socket

  # The author of a post is a BelongsTo field with an `options_query` that excludes deleted users.
  describe "options_query" do
    test "refuses to save an author that is not an option", %{conn: conn} do
      post = insert(:post)
      deleted_user = insert(:user, deleted_at: DateTime.utc_now(:second))

      conn
      |> visit(~p"/admin/posts/#{post.id}/edit")
      |> save(%{user_id: deleted_user.id})
      |> assert_has("#resource-form_user_id-errors > p.text-error", text: "is invalid", exact: true)

      assert Repo.get!(Post, post.id).user_id == post.user_id
    end

    test "refuses to create an item with an author that is not an option", %{conn: conn} do
      deleted_user = insert(:user, deleted_at: DateTime.utc_now(:second))

      conn
      |> visit(~p"/admin/posts/new")
      |> save(%{title: "Title", body: "Body", user_id: deleted_user.id})

      refute Repo.get_by(Post, title: "Title")
    end

    test "saves an author that is an option", %{conn: conn} do
      post = insert(:post)
      other_user = insert(:user)

      conn
      |> visit(~p"/admin/posts/#{post.id}/edit")
      |> save(%{user_id: other_user.id})

      assert Repo.get!(Post, post.id).user_id == other_user.id
    end

    test "keeps the author of the item that is no longer an option", %{conn: conn} do
      deleted_user = insert(:user, deleted_at: DateTime.utc_now(:second))
      post = insert(:post, user: deleted_user)

      conn
      |> visit(~p"/admin/posts/#{post.id}/edit")
      |> save(%{title: "After", user_id: deleted_user.id})

      assert %Post{title: "After", user_id: user_id} = Repo.get!(Post, post.id)
      assert user_id == deleted_user.id
    end
  end

  # `Backpex.Test.ProductShortLinksLive` has a BelongsTo field of `Backpex.Test.ShortLink`, whose key is `short_key`.
  describe "a related schema whose key is not id" do
    @combobox "#resource-form_featured_short_link_key"

    setup do
      # The keys come from the factory's sequence: equal keys would make concurrent tests wait for each other.
      link = insert(:short_link, url: "https://docs.example.com/")
      other_link = insert(:short_link, url: "https://blog.example.com/")

      %{product: insert(:product, featured_short_link: link), link: link, other_link: other_link}
    end

    test "renders the keys as option values and selects the current one", context do
      %{conn: conn, product: product, link: link, other_link: other_link} = context

      conn
      |> visit(~p"/admin/product-short-links/#{product.id}/edit")
      |> assert_has("label[for=resource-form_featured_short_link_key-trigger]", text: "Featured Short Link")
      |> assert_has("#{@combobox} [data-part=value-label]", text: "https://docs.example.com/", exact: true)
      |> assert_has("#{@combobox} input[name='change[featured_short_link_key]'][value='#{link.short_key}']")
      |> assert_has("#{@combobox} [role=option][data-value='#{link.short_key}'][aria-selected=true]",
        text: link.url,
        exact: true
      )
      |> assert_has("#{@combobox} [role=option][data-value='#{other_link.short_key}'][aria-selected=false]",
        text: other_link.url,
        exact: true
      )
    end

    test "saves the key of the chosen option", %{conn: conn, product: product, other_link: other_link} do
      conn
      |> visit(~p"/admin/product-short-links/#{product.id}/edit")
      |> set_combobox("change[featured_short_link_key]", other_link.short_key)
      |> assert_has("#{@combobox} [data-part=value-label]", text: other_link.url, exact: true)
      |> click_button("Save")
      |> assert_path(~p"/admin/product-short-links")

      assert Repo.get!(Product, product.id).featured_short_link_key == other_link.short_key
    end

    test "refuses to save a key that no related item has", %{conn: conn, product: product, link: link} do
      conn
      |> visit(~p"/admin/product-short-links/#{product.id}/edit")
      |> save(%{featured_short_link_key: "missing"})

      assert Repo.get!(Product, product.id).featured_short_link_key == link.short_key
    end
  end

  # The author of `Backpex.Test.PostRelationOptionsLive` is an index editable BelongsTo field with a `query_limit` of 2
  # and no prompt. Its options are labelled and ordered by the first name.
  describe "query_limit" do
    @combobox "#resource-form_user_id"

    setup do
      users = for name <- ~w[Anna Bert Carl], do: insert(:user, first_name: name)

      %{users: users, post: insert(:post, user: List.last(users))}
    end

    test "loads a page of options and shows the current value that is on no loaded page", context do
      %{conn: conn, post: post, users: [anna, bert, carl]} = context

      conn
      |> visit(~p"/admin/post-relation-options/#{post.id}/edit")
      |> assert_has("#{@combobox} [role=option]", count: 2)
      |> assert_has("#{@combobox} [role=option][data-value='#{anna.id}']", text: "Anna", exact: true)
      |> assert_has("#{@combobox} [role=option][data-value='#{bert.id}']", text: "Bert", exact: true)
      |> assert_has("#{@combobox} [data-part=value-label]", text: "Carl", exact: true)
      |> assert_has("#{@combobox} input[name='change[user_id]'][value='#{carl.id}']")
      |> assert_has("#{@combobox}[data-on-search=search]")
      |> assert_has("#{@combobox}-search")
      |> assert_has("#{@combobox}-popup button", text: "Show more")
    end

    test "loads the next page with show more", %{conn: conn, post: post} do
      conn
      |> visit(~p"/admin/post-relation-options/#{post.id}/edit")
      |> unwrap(&(&1 |> element("#{@combobox}-popup button", "Show more") |> render_click()))
      |> assert_has("#{@combobox} [role=option]", count: 3)
      |> refute_has("#{@combobox}-popup button", text: "Show more")
    end

    test "searches the options on the server by display_field_form", %{conn: conn, post: post, users: [_anna, bert | _]} do
      conn
      |> visit(~p"/admin/post-relation-options/#{post.id}/edit")
      |> search("#{@combobox}", "ER")
      |> assert_has("#{@combobox} [role=option]", count: 1)
      |> assert_has("#{@combobox} [role=option][data-value='#{bert.id}']", text: "Bert", exact: true)
      |> refute_has("#{@combobox}-popup button", text: "Show more")
      # The current value stays, although the search does not find it.
      |> assert_has("#{@combobox} [data-part=value-label]", text: "Carl", exact: true)
      # The combobox pushes an empty search when its popup closes.
      |> search("#{@combobox}", "")
      |> assert_has("#{@combobox} [role=option]", count: 2)
    end

    test "selects the first option of the options query while a new item has no value", %{conn: conn, users: users} do
      [anna, _bert, carl] = users

      conn
      |> visit(~p"/admin/post-relation-options/new")
      |> assert_has("#{@combobox} input[name='change[user_id]'][value='#{anna.id}']")
      # A search does not change the value, even if its results don't contain the first option.
      |> search("#{@combobox}", "Carl")
      |> assert_has("#{@combobox} [role=option]", count: 1)
      |> assert_has("#{@combobox} [role=option][data-value='#{carl.id}']")
      |> assert_has("#{@combobox} input[name='change[user_id]'][value='#{anna.id}']")
      |> assert_has("#{@combobox} [data-part=value-label]", text: "Anna", exact: true)
    end

    test "saves an option found by the search", %{conn: conn, post: post, users: [_anna, bert | _]} do
      conn
      |> visit(~p"/admin/post-relation-options/#{post.id}/edit")
      |> search("#{@combobox}", "Bert")
      |> set_combobox("change[user_id]", bert.id)
      |> assert_has("#{@combobox} [data-part=value-label]", text: "Bert", exact: true)
      |> click_button("Save")
      |> assert_path(~p"/admin/post-relation-options")

      assert Repo.get!(Post, post.id).user_id == bert.id
    end

    # The check uses the whole options query, not the loaded page.
    test "saves an option that is on no loaded page and refuses an id that no option has", context do
      %{conn: conn, users: [anna | _users]} = context
      post = insert(:post, user: anna)
      dave = insert(:user, first_name: "Dave")

      conn
      |> visit(~p"/admin/post-relation-options/#{post.id}/edit")
      |> save(%{user_id: dave.id})

      assert Repo.get!(Post, post.id).user_id == dave.id

      conn
      |> visit(~p"/admin/post-relation-options/#{post.id}/edit")
      |> save(%{user_id: dave.id + 1000})
      |> assert_has("#{@combobox}-errors > p.text-error", text: "is invalid", exact: true)

      assert Repo.get!(Post, post.id).user_id == dave.id
    end

    test "searches and saves on the index view", %{conn: conn, post: post, users: [anna, bert, carl]} do
      combobox = "#index-form-input-user-#{post.id}"

      session =
        conn
        |> visit(~p"/admin/post-relation-options")
        |> assert_has("#{combobox} [role=option]", count: 2)
        |> assert_has("#{combobox} [role=option][data-value='#{anna.id}']")
        |> assert_has("#{combobox} [data-part=value-label]", text: "Carl", exact: true)
        |> assert_has("#{combobox}-popup button", text: "Show more")
        |> search(combobox, "ert")
        |> assert_has("#{combobox} [role=option]", count: 1)
        |> assert_has("#{combobox} [role=option][data-value='#{bert.id}']")
        |> unwrap(
          &(&1
            |> element("#index-form-user-#{post.id}")
            |> render_change(%{"index_form" => %{"value" => bert.id}}))
        )

      assert Repo.get!(Post, post.id).user_id == bert.id

      session
      |> assert_has("#{combobox} [data-part=value-label]", text: "Bert", exact: true)
      |> search(combobox, "")
      |> assert_has("#{combobox} [role=option]", count: 2)
      |> refute_has("#{combobox} [role=option][data-value='#{carl.id}']")
    end

    # The index view loads the options for all rows at once: a page of options and the options of the rows' values.
    test "loads the options of all rows with a constant number of queries", %{post: post, users: [anna, bert, carl]} do
      field = Enum.find(PostRelationOptionsLive.fields(), &(elem(&1, 0) == :user))
      assigns = %{live_resource: PostRelationOptionsLive, live_action: :index}
      other_post = insert(:post, user: bert)
      posts = [post, other_post | insert_list(4, :post, user: anna)]

      few_rows_queries = count_queries("users", fn -> BelongsTo.index_assigns(field, [post], assigns) end)
      many_rows_queries = count_queries("users", fn -> BelongsTo.index_assigns(field, posts, assigns) end)

      assert few_rows_queries > 0
      assert many_rows_queries == few_rows_queries

      %{index_form_pages: pages} = BelongsTo.index_assigns(field, posts, assigns)

      assert %{options: options, option_records: records, show_more: true, selected_option: selected} = pages[post.id]
      assert options == [{"Anna", anna.id}, {"Bert", bert.id}]
      assert Enum.map(records, & &1.id) == [anna.id, bert.id]
      assert selected == {"Carl", carl.id}

      assert pages[other_post.id].selected_option == {"Bert", bert.id}
    end

    # The author of `Backpex.Test.PostLive` is labelled with a `full_name` that its options query selects, and its
    # `select` expression is the same full name.
    test "searches by the select expression of the field", %{users: [anna | _users]} do
      anna = anna |> Ecto.Changeset.change(last_name: "Smith") |> Repo.update!()
      {name, field_options} = Enum.find(PostLive.fields(), &(elem(&1, 0) == :user))
      field_options = Map.merge(field_options, %{searchable_options: :server, query_limit: 2})

      assigns = %{
        type: :form,
        name: name,
        field: {name, field_options},
        field_options: field_options,
        live_resource: PostLive,
        form: %Post{} |> Ecto.Changeset.change() |> Phoenix.Component.to_form(as: :change)
      }

      {:ok, socket} = BelongsTo.update(assigns, %Socket{})
      {:noreply, socket} = BelongsTo.handle_event("search", %{"query" => "anna smi"}, socket)

      assert socket.assigns.options == [{"Anna Smith", anna.id}]
    end

    test "loads the options again when the options query changes", %{users: [anna, bert, carl]} do
      {name, field_options} = Enum.find(PostRelationOptionsLive.fields(), &(elem(&1, 0) == :user))

      field_options =
        Map.put(field_options, :options_query, fn query, assigns ->
          where(query, [user], user.first_name >= ^(Form.input_value(assigns.form, :title) || ""))
        end)

      assigns = fn title ->
        %{
          type: :form,
          name: name,
          field: {name, field_options},
          field_options: field_options,
          live_resource: PostRelationOptionsLive,
          form: %Post{user_id: anna.id} |> Ecto.Changeset.change(title: title) |> Phoenix.Component.to_form(as: :change)
        }
      end

      {:ok, socket} = "A" |> assigns.() |> BelongsTo.update(%Socket{})

      assert socket.assigns.options == [{"Anna", anna.id}, {"Bert", bert.id}]
      assert socket.assigns.selected_option == {"Anna", anna.id}
      assert count_queries("users", fn -> "A" |> assigns.() |> BelongsTo.update(socket) end) == 0

      {:ok, socket} = "B" |> assigns.() |> BelongsTo.update(socket)

      assert socket.assigns.options == [{"Bert", bert.id}, {"Carl", carl.id}]
      # The current value is no longer an option, so it has no label.
      assert socket.assigns.selected_option == nil
    end

    test "keeps the first option of the options query as the default while a search is active", context do
      %{users: [_anna, bert, _carl]} = context
      {name, field_options} = Enum.find(PostRelationOptionsLive.fields(), &(elem(&1, 0) == :user))

      field_options =
        Map.put(field_options, :options_query, fn query, assigns ->
          where(query, [user], user.first_name >= ^(Form.input_value(assigns.form, :title) || ""))
        end)

      assigns = fn title, user_id ->
        %{
          type: :form,
          name: name,
          field: {name, field_options},
          field_options: field_options,
          live_resource: PostRelationOptionsLive,
          form: %Post{user_id: user_id} |> Ecto.Changeset.change(title: title) |> Phoenix.Component.to_form(as: :change)
        }
      end

      {:ok, socket} = "A" |> assigns.(nil) |> BelongsTo.update(%Socket{})
      {:noreply, socket} = BelongsTo.handle_event("search", %{"query" => "Carl"}, socket)
      {:ok, socket} = "B" |> assigns.(nil) |> BelongsTo.update(socket)

      assert socket.assigns.default_option == {"Bert", bert.id}

      # A value that is no valid key of the options has no option.
      {:ok, socket} = "B" |> assigns.("invalid") |> BelongsTo.update(socket)

      assert socket.assigns.selected_option == nil
    end

    # A row that is not among the items of `c:Backpex.Field.index_assigns/3` loads its own page.
    test "loads the page of an index row without the options of the index view", %{post: post, users: users} do
      [anna, bert, carl] = users
      {name, field_options} = Enum.find(PostRelationOptionsLive.fields(), &(elem(&1, 0) == :user))

      assigns = %{
        type: :index,
        name: name,
        field: {name, field_options},
        field_options: field_options,
        live_resource: PostRelationOptionsLive,
        live_action: :index,
        item: post,
        value: post.user
      }

      {:ok, socket} = BelongsTo.update(assigns, %Socket{})

      assert socket.assigns.options == [{"Anna", anna.id}, {"Bert", bert.id}]
      assert socket.assigns.show_more
      assert socket.assigns.selected_option == {"Carl", carl.id}

      {:noreply, socket} = BelongsTo.handle_event("show-more", %{}, socket)

      assert length(socket.assigns.options) == 3
    end
  end

  # The combobox pushes the text of its search input to the field.
  defp search(session, combobox, query) do
    unwrap(session, &(&1 |> element(combobox) |> render_hook("search", %{"query" => query})))
  end

  # A crafted client can send any value, not only the options of the select.
  defp save(session, params) do
    unwrap(session, fn view ->
      view
      |> form("#resource-form")
      |> put_submitter("button[value=save]")
      |> render_submit(%{change: params})
    end)
  end
end
