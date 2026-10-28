defmodule Backpex.Integration.Options.ScopeTest do
  @moduledoc """
  Checks `c:Backpex.LiveResource.scope/1` and the `:options_filter` option of relation fields through
  `Backpex.Test.ScopedPostLive`, which shows the published posts only.
  """
  use Backpex.ConnCase, async: true

  describe "scope/1" do
    setup do
      %{
        published: insert(:post, title: "Published post", published: true),
        draft: insert(:post, title: "Draft post", published: false)
      }
    end

    test "limits the items and the count of the index view", %{conn: conn} do
      # With the 16 drafts, the 17 posts would fill a second page of 15 items.
      insert_list(15, :post, published: false)

      conn
      |> visit(~p"/admin/scoped-posts")
      |> assert_has("table tbody tr", count: 1)
      |> assert_has("td", text: "Published post")
      |> refute_has("td", text: "Draft post")
      |> assert_has("[aria-current=page]", text: "1")
      |> refute_has("a", text: "2", exact: true)

      # The same posts without the scope.
      conn
      |> visit(~p"/admin/post-relation-options")
      |> assert_has("a", text: "2", exact: true)
    end

    test "applies with a search", %{conn: conn} do
      conn
      |> visit(~p"/admin/scoped-posts?#{%{search: "post"}}")
      |> assert_has("table tbody tr", count: 1)
      |> assert_has("td", text: "Published post")
    end

    test "hides the items outside of it from the show and edit views", %{conn: conn, draft: draft} do
      assert_error_sent 404, fn -> get(conn, ~p"/admin/scoped-posts/#{draft.id}/show") end
      assert_error_sent 404, fn -> get(conn, ~p"/admin/scoped-posts/#{draft.id}/edit") end
    end

    test "keeps the items inside of it on the show view", %{conn: conn, published: published} do
      conn
      |> visit(~p"/admin/scoped-posts/#{published.id}/show")
      |> assert_has("dd", text: "Published post")
    end
  end

  describe "options_filter" do
    test "limits the options of a belongs to field to the items that match the expression", %{conn: conn} do
      insert(:user, username: "visible_author")
      insert(:user, username: "hidden_author")

      conn
      |> visit(~p"/admin/scoped-posts/new")
      |> assert_has("select option", text: "visible_author")
      |> refute_has("select option", text: "hidden_author")
    end

    test "limits the options of a has many field to the result of a function of the assigns", %{conn: conn} do
      insert(:tag, name: "Elixir")
      insert(:tag, name: "Hidden tag")
      post = insert(:post, published: true, tags: [])

      conn
      |> visit(~p"/admin/scoped-posts/new")
      |> assert_has("#has-many-tags label span", text: "Elixir", exact: true)
      |> refute_has("#has-many-tags label span", text: "Hidden tag")

      # The function returns nil for the edit form, which keeps all options.
      conn
      |> visit(~p"/admin/scoped-posts/#{post.id}/edit")
      |> assert_has("#has-many-tags label span", text: "Hidden tag", exact: true)
    end
  end
end
