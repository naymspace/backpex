defmodule DemoWeb.Browser.TagBrowserTest do
  use PhoenixTest.Playwright.Case, async: false
  use DemoWeb, :verified_routes
  use DemoWeb.A11yAssertions

  import Demo.EctoFactory

  @moduletag :playwright

  describe "tags index" do
    test "a11y", %{conn: conn} do
      insert_list(10, :tag)

      conn
      |> visit(~p"/admin/tags")
      |> assert_a11y()
    end
  end

  describe "tags show" do
    test "a11y", %{conn: conn} do
      tag = insert(:tag)

      conn
      |> visit(~p"/admin/tags/#{tag.id}/show")
      |> assert_a11y()
    end
  end

  describe "tags edit" do
    test "a11y", %{conn: conn} do
      tag = insert(:tag)

      conn
      |> visit(~p"/admin/tags/#{tag.id}/edit")
      |> assert_a11y()
    end
  end

  describe "tags new" do
    test "a11y", %{conn: conn} do
      conn
      |> visit(~p"/admin/tags/new")
      |> assert_a11y()
    end
  end
end
