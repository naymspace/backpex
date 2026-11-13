defmodule Backpex.Integration.Options.RelationFieldOptionsTest do
  use Backpex.ConnCase, async: true

  import Phoenix.LiveViewTest, only: [element: 2, render_hook: 3]

  alias Backpex.Test.UsersAddresses

  # `Backpex.Test.PostRelationOptionsLive` and `Backpex.Test.UserRelationOptionsLive` set the options, while
  # `Backpex.Test.PostLive` and `Backpex.Test.UserLive` leave them at their defaults.

  describe "display_field_form of Backpex.Fields.BelongsTo" do
    test "labels the options of the form, while the show view keeps display_field", %{conn: conn} do
      post = insert(:post, user: build(:user, username: "jdoe", first_name: "Jane"))

      conn
      |> visit(~p"/admin/post-relation-options/#{post.id}/edit")
      |> assert_has("label[for=resource-form_user_id-trigger]", text: "Author")
      |> assert_has("#resource-form_user_id [data-part=value-label]", text: "Jane", exact: true)
      |> assert_has("#resource-form_user_id [role=option][aria-selected=true]", text: "Jane", exact: true)
      |> refute_has("#resource-form_user_id [role=option]", text: "jdoe")

      conn
      |> visit(~p"/admin/post-relation-options/#{post.id}/show")
      |> assert_has("dd a", text: "jdoe", exact: true)
    end
  end

  describe "display_field_form of Backpex.Fields.HasMany" do
    setup do
      user = insert(:user, posts: [build(:post, title: "Hello", body: "Hello body", user: nil)])
      insert(:post, title: "Other", body: "Other body")

      %{user: user}
    end

    test "labels the options and the selected badges of the form", %{conn: conn, user: user} do
      conn
      |> visit(~p"/admin/user-relation-options/#{user.id}/edit")
      |> assert_has("#has-many-posts [role=option][aria-selected=true]", text: "Hello body", exact: true)
      |> assert_has("#has-many-posts [role=option][aria-selected=false]", text: "Other body", exact: true)
      |> assert_has("#has-many-posts [data-part=badge-label]", text: "Hello body", exact: true)
      |> refute_has("#has-many-posts span", text: "Hello", exact: true)
    end

    test "keeps display_field on the show view", %{conn: conn, user: user} do
      conn
      |> visit(~p"/admin/user-relation-options/#{user.id}/show")
      |> assert_has("dd a", text: "Hello", exact: true)
      |> refute_has("dd", text: "Hello body")
    end
  end

  describe "link_assocs of Backpex.Fields.HasMany" do
    setup do
      %{post: insert(:post, tags: [build(:tag, name: "Elixir")])}
    end

    test "renders the items as text when false", %{conn: conn, post: post} do
      conn
      |> visit(~p"/admin/post-relation-options")
      |> assert_has("td span", text: "Elixir", exact: true)
      |> refute_has("td a", text: "Elixir")

      conn
      |> visit(~p"/admin/post-relation-options/#{post.id}/show")
      |> assert_has("dd span", text: "Elixir", exact: true)
      |> refute_has("dd a", text: "Elixir")
    end

    test "links the items to the show view of their LiveResource by default", %{conn: conn, post: post} do
      [tag] = post.tags

      conn
      |> visit(~p"/admin/posts")
      |> assert_has("td a[href='/admin/tags/#{tag.id}/show']", text: "Elixir", exact: true)

      conn
      |> visit(~p"/admin/posts/#{post.id}/show")
      |> assert_has("dd a[href='/admin/tags/#{tag.id}/show']", text: "Elixir", exact: true)
    end
  end

  describe "prompt and not_found_text of Backpex.Fields.HasMany" do
    setup do
      insert(:tag, name: "Elixir")
      :ok
    end

    test "are shown without a selection and for a search without options", %{conn: conn} do
      conn
      |> visit(~p"/admin/post-relation-options/new")
      |> assert_has("#has-many-tags [data-part=placeholder]:not([hidden])", text: "Pick some tags", exact: true)
      |> assert_has("#has-many-tags [role=option]", text: "Elixir", exact: true)
      # The empty state is rendered hidden while there are options.
      |> assert_has("#has-many-tags [data-part=empty][hidden]", text: "No tags match", exact: true)
      |> search_tags("zzz")
      |> refute_has("#has-many-tags [role=option]")
      |> assert_has("#has-many-tags [data-part=empty]:not([hidden])", text: "No tags match", exact: true)
      |> refute_has("#has-many-tags", text: "No options found")
    end

    test "default to Backpex's texts", %{conn: conn} do
      conn
      |> visit(~p"/admin/posts/new")
      |> assert_has("#has-many-tags [data-part=placeholder]:not([hidden])", text: "Select options...", exact: true)
      |> search_tags("zzz")
      |> assert_has("#has-many-tags [data-part=empty]:not([hidden])", text: "No options found", exact: true)
    end
  end

  describe "sort_by of Backpex.Fields.HasManyThrough" do
    test "orders the rows by the columns of the child", %{conn: conn} do
      users_addresses =
        for city <- ~w[Munich Berlin Hamburg] do
          %UsersAddresses{address: build(:address, city: city), type: :billing}
        end

      user = insert(:user, users_addresses: users_addresses)

      conn
      |> visit(~p"/admin/user-relation-options/#{user.id}/show")
      |> assert_rows("dd tbody", ~w[Berlin Hamburg Munich])

      conn
      |> visit(~p"/admin/user-relation-options/#{user.id}/edit")
      |> assert_rows("table[aria-labelledby='has-many-through-label-addresses'] tbody", ~w[Berlin Hamburg Munich])
    end
  end

  # The combobox pushes the text of its search input to the field.
  defp search_tags(session, search) do
    unwrap(session, fn view ->
      view
      |> element("#resource-form_tags")
      |> render_hook("search", %{"query" => search, "id" => "resource-form_tags"})
    end)
  end

  describe "readonly child field of Backpex.Fields.InlineCRUD" do
    test "saves the editable child fields and keeps the readonly one", %{conn: conn} do
      user = insert(:user)
      [link] = user.social_links

      conn
      |> visit(~p"/admin/user-relation-options/#{user.id}/edit")
      |> assert_has("input[name='change[social_links][0][url]'][readonly]")
      # A crafted client can still send a value for the readonly input.
      |> unwrap(fn view ->
        view
        |> Phoenix.LiveViewTest.form("#resource-form")
        |> Phoenix.LiveViewTest.put_submitter("button[value=save]")
        |> Phoenix.LiveViewTest.render_submit(%{
          change: %{social_links: %{"0" => %{id: link.id, label: "Blog", url: "https://forged.example.com"}}}
        })
      end)

      assert [%{label: "Blog", url: "https://example.com/"}] = Repo.reload!(user).social_links
    end
  end
end
