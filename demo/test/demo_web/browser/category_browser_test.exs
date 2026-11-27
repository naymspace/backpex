defmodule DemoWeb.Browser.CategoryBrowserTest do
  use DemoWeb.BrowserCase, async: false
  use DemoWeb, :verified_routes
  use DemoWeb.A11yAssertions

  import Demo.EctoFactory

  @moduletag :playwright

  describe "categories index" do
    test "a11y", %{session: session} do
      insert_list(10, :category)

      session
      |> visit(~p"/admin/categories")
      |> assert_a11y()
    end
  end

  describe "categories show" do
    test "a11y", %{session: session} do
      category = insert(:category)

      session
      |> visit(~p"/admin/categories/#{category.id}/show")
      |> assert_a11y()
    end
  end

  describe "categories edit" do
    test "a11y", %{session: session} do
      category = insert(:category)

      session
      |> visit(~p"/admin/categories/#{category.id}/edit")
      |> assert_a11y()
    end
  end

  describe "categories new" do
    test "a11y", %{session: session} do
      session
      |> visit(~p"/admin/categories/new")
      |> assert_a11y()
    end
  end
end
