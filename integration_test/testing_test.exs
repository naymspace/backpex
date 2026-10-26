defmodule Backpex.TestingTest do
  use Backpex.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Backpex.Test.Category
  alias Backpex.Test.CategoryLive
  alias Backpex.Test.PostLive
  alias Backpex.Test.Router
  alias Backpex.Test.ShortLinkLive
  alias Backpex.Test.Tag
  alias Backpex.Test.TagLive
  alias Backpex.Test.UserLive
  alias Backpex.Testing

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

    test "raises for a view the router does not route" do
      assert_raise ArgumentError, ~r/Could not find route/, fn ->
        Testing.path(Router, Backpex.Test.InvoiceLive, :new)
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
      [category, other_category] = insert_list(2, :category)
      {:ok, view, _html} = live(conn, Testing.path(Router, CategoryLive, :index))

      view
      |> Testing.select_item(category)
      |> Testing.select_item(other_category)
      |> Testing.click_item_action(:delete)
      |> Testing.confirm_item_action()

      assert Repo.all(Category) == []
    end

    test "fill in the fields of an item action", %{conn: conn} do
      tag = insert(:tag, name: "Elixir")
      {:ok, view, _html} = live(conn, Testing.path(Router, TagLive, :show, tag))

      view
      |> Testing.click_item_action(:duplicate)
      |> Testing.confirm_item_action(%{name: "Phoenix"})

      assert Tag |> Repo.all() |> Enum.map(& &1.name) |> Enum.sort() == ["Elixir", "Phoenix"]
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
      assert Repo.get!(Backpex.Test.Post, post.id).title == "Updated"
    end
  end
end
