defmodule Backpex.TestingTest do
  use Backpex.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Backpex.Test.Category
  alias Backpex.Test.CategoryLive
  alias Backpex.Test.Post
  alias Backpex.Test.PostLive
  alias Backpex.Test.Router
  alias Backpex.Test.ShortLinkLive
  alias Backpex.Test.Tag
  alias Backpex.Test.TagLive
  alias Backpex.Test.UserLive
  alias Backpex.Testing

  # The router of the test app has no route params, so the tests of route params build paths with this router.
  defmodule TenantRouter do
    use Phoenix.Router

    import Backpex.Router
    import Phoenix.LiveView.Router

    scope "/:tenant/admin" do
      live_session :tenant do
        live_resources "/tags", TagLive
      end
    end
  end

  describe "path/5" do
    test "returns the path of every view" do
      tag = insert(:tag)

      assert Testing.path(Router, TagLive, :index) == "/admin/tags"
      assert Testing.path(Router, TagLive, :new) == "/admin/tags/new"
      assert Testing.path(Router, TagLive, :show, tag) == "/admin/tags/#{tag.id}/show"
      assert Testing.path(Router, TagLive, :edit, tag.id) == "/admin/tags/#{tag.id}/edit"
      assert Testing.path(Router, UserLive, :resource_action, :invite) == "/admin/users/invite/resource-action"
    end

    test "encodes the primary value of an item" do
      short_link = insert(:short_link, short_key: "with space")

      assert Testing.path(Router, ShortLinkLive, :show, short_link) == "/admin/short-links/with%20space/show"
    end

    test "puts route params of any type into the path" do
      tag = insert(:tag)

      assert Testing.path(TenantRouter, TagLive, :index, params: [tenant: 42]) == "/42/admin/tags"
      assert Testing.path(TenantRouter, TagLive, :new, params: %{"tenant" => "acme"}) == "/acme/admin/tags/new"
      assert Testing.path(TenantRouter, TagLive, :show, tag, params: %{tenant: 42}) == "/42/admin/tags/#{tag.id}/show"
    end

    test "appends query params" do
      tag = insert(:tag)

      assert Testing.path(Router, TagLive, :index, query: [page: 2, order_by: "name"]) ==
               "/admin/tags?page=2&order_by=name"

      assert Testing.path(TenantRouter, TagLive, :edit, tag, params: [tenant: 42], query: %{tab: "main"}) ==
               "/42/admin/tags/#{tag.id}/edit?tab=main"
    end

    test "takes an empty list or a string instead of no item or an atom key" do
      assert Testing.path(Router, TagLive, :index, [], query: [page: 2]) == "/admin/tags?page=2"
      assert Testing.path(Router, UserLive, :resource_action, "invite") == "/admin/users/invite/resource-action"
    end

    test "raises for an item without a primary value" do
      assert_raise ArgumentError, ~r/the item has no primary value/, fn ->
        Testing.path(Router, TagLive, :show, %Tag{})
      end
    end

    test "raises for options in place of the item" do
      assert_raise ArgumentError, ~r/expected an item or its primary value, got: \[query:/, fn ->
        Testing.path(Router, TagLive, :show, query: [page: 2])
      end
    end

    test "raises with the valid forms for invalid arguments" do
      for args <- [[:index, %{id: 1}, []], [:resource_action, nil, []], [:unknown, nil, []]] do
        assert_raise ArgumentError, ~r/Valid forms are/, fn -> apply(Testing, :path, [Router, TagLive | args]) end
      end
    end

    test "raises for a view the router does not route" do
      assert_raise ArgumentError, ~r/Could not find route/, fn ->
        Testing.path(Router, Backpex.Test.InvoiceLive, :new)
      end
    end
  end

  describe "select_item/2 and deselect_item/2" do
    test "select and deselect regardless of the current selection", %{conn: conn} do
      category = insert(:category)
      {:ok, view, _html} = live(conn, Testing.path(Router, CategoryLive, :index))
      checked = ~s|input[id="select-input-#{category.id}"][checked]|

      view
      |> Testing.select_item(category)
      |> Testing.select_item(category)

      assert has_element?(view, checked)

      view
      |> Testing.deselect_item(category)
      |> Testing.deselect_item(category.id)

      refute has_element?(view, checked)
    end

    test "find the row of a primary value with quotes and backslashes", %{conn: conn} do
      # ShortLinkLive denies the only bulk item action, so the checkbox exists but is disabled.
      short_link = insert(:short_link, short_key: ~S(a"b\c))
      {:ok, view, _html} = live(conn, Testing.path(Router, ShortLinkLive, :index))

      assert Testing.deselect_item(view, short_link) == view

      assert_raise ArgumentError, ~r/because it is disabled/, fn ->
        Testing.select_item(view, short_link)
      end
    end

    test "raise for an item without a row on the index view", %{conn: conn} do
      insert(:category)
      {:ok, view, _html} = live(conn, Testing.path(Router, CategoryLive, :index))
      missing_id = Ecto.UUID.generate()

      assert_raise ArgumentError, ~r/the index view has no row/, fn -> Testing.select_item(view, missing_id) end
      assert_raise ArgumentError, ~r/the index view has no row/, fn -> Testing.deselect_item(view, missing_id) end
    end

    test "raise for an item on a view that isn't a view of a LiveResource" do
      for module <- [Router, :"Elixir.UnknownNamespace.Index"] do
        view = %Phoenix.LiveViewTest.View{module: module}

        assert_raise ArgumentError, ~r/Pass the primary value instead of the item/, fn ->
          Testing.select_item(view, %{id: 1})
        end
      end
    end
  end

  describe "click_item_action/3 and confirm_item_action/2" do
    test "delete an item from its row", %{conn: conn} do
      category = insert(:category)
      {:ok, view, _html} = live(conn, Testing.path(Router, CategoryLive, :index))

      view
      |> Testing.click_item_action(:delete, category)
      |> Testing.confirm_item_action()

      refute Repo.get(Category, category.id)
    end

    test "delete the selected items", %{conn: conn} do
      [category, other_category, kept_category] = insert_list(3, :category)
      {:ok, view, _html} = live(conn, Testing.path(Router, CategoryLive, :index))

      view
      |> Testing.select_item(category)
      |> Testing.select_item(other_category)
      |> Testing.select_item(other_category)
      |> Testing.click_item_action(:delete)
      |> Testing.confirm_item_action()

      assert [%Category{id: id}] = Repo.all(Category)
      assert id == kept_category.id
    end

    test "fill in the fields of an item action", %{conn: conn} do
      tag = insert(:tag, name: "Elixir")
      {:ok, view, _html} = live(conn, Testing.path(Router, TagLive, :show, tag))

      view
      |> Testing.click_item_action(:duplicate)
      |> Testing.confirm_item_action(%{name: "Phoenix"})

      assert Tag |> Repo.all() |> Enum.map(& &1.name) |> Enum.sort() == ["Elixir", "Phoenix"]
    end

    test "follow a link item action from a row", %{conn: conn} do
      short_link = insert(:short_link, short_key: ~S(a"b\c))
      {:ok, view, _html} = live(conn, Testing.path(Router, ShortLinkLive, :index))

      Testing.click_item_action(view, :show, short_link)

      {path, _flash} = assert_redirect(view)
      assert path == Testing.path(Router, ShortLinkLive, :show, short_link)
      assert {:ok, _view, _html} = live(conn, path)
    end

    test "follow a link item action from the show view", %{conn: conn} do
      tag = insert(:tag)
      {:ok, view, _html} = live(conn, Testing.path(Router, TagLive, :show, tag))

      Testing.click_item_action(view, :edit)

      {path, _flash} = assert_redirect(view)

      assert path ==
               Testing.path(Router, TagLive, :edit, tag, query: [return_to: Testing.path(Router, TagLive, :show, tag)])

      assert {:ok, _view, _html} = live(conn, path)
    end
  end

  describe "submit_form/3" do
    test "saves the new form", %{conn: conn} do
      {:ok, view, _html} = live(conn, Testing.path(Router, CategoryLive, :new))

      Testing.submit_form(view, %{name: "News"})

      assert_redirect(view, Testing.path(Router, CategoryLive, :index))
      assert [%Category{name: "News"}] = Repo.all(Category)
    end

    test "submits with another button", %{conn: conn} do
      post = insert(:post)
      {:ok, view, _html} = live(conn, Testing.path(Router, PostLive, :edit, post))

      Testing.submit_form(view, %{title: "Updated"}, "continue")

      assert_redirect(view, Testing.path(Router, PostLive, :edit, post))
      assert Repo.get!(Post, post.id).title == "Updated"
    end

    test "submits with a custom form action", %{conn: conn} do
      post = insert(:post)
      {:ok, view, _html} = live(conn, Testing.path(Router, PostLive, :edit, post))

      Testing.submit_form(view, %{title: "Updated"}, :show)

      assert_redirect(view, Testing.path(Router, PostLive, :show, post))
      assert Repo.get!(Post, post.id).title == "Updated"
    end
  end
end
