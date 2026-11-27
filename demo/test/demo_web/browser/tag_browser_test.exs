defmodule DemoWeb.Browser.TagBrowserTest do
  use DemoWeb.BrowserCase, async: false
  use DemoWeb, :verified_routes
  use DemoWeb.A11yAssertions

  import Demo.EctoFactory

  @moduletag :playwright

  describe "tags index" do
    test "a11y", %{session: session} do
      insert_list(10, :tag)

      session
      |> visit(~p"/admin/tags")
      |> assert_a11y()
    end
  end

  describe "tags show" do
    test "a11y", %{session: session} do
      tag = insert(:tag)

      session
      |> visit(~p"/admin/tags/#{tag.id}/show")
      |> assert_a11y()
    end
  end

  describe "tags edit" do
    test "a11y", %{session: session} do
      tag = insert(:tag)

      session
      |> visit(~p"/admin/tags/#{tag.id}/edit")
      |> assert_a11y()
    end
  end

  describe "tags new" do
    test "a11y", %{session: session} do
      session
      |> visit(~p"/admin/tags/new")
      |> assert_a11y()
    end
  end
end
