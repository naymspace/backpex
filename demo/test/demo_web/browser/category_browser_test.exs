defmodule DemoWeb.Browser.CategoryBrowserTest do
  use PhoenixTest.Playwright.Case, async: false
  use DemoWeb, :verified_routes
  use DemoWeb.A11yAssertions

  # import Demo.EctoFactory

  @moduletag :external

  describe "categories index" do
    test "a11y", %{conn: conn} do
      conn
      |> visit(~p"/admin/categories")

      # |> assert_a11y()
    end
  end

  # describe "categories show" do
  #   test "a11y", %{conn: conn} do
  #     category = insert(:category)

  #     conn
  #     |> visit(~p"/admin/categories/#{category.id}/edit")
  #     |> assert_a11y()
  #   end
  # end

  # describe "categories edit" do
  #   test "a11y", %{conn: conn} do
  #     category = insert(:category)

  #     conn
  #     |> visit(~p"/admin/categories/#{category.id}/edit")
  #     |> assert_a11y()
  #   end
  # end

  # describe "categories new" do
  #   test "a11y", %{conn: conn} do
  #     conn
  #     |> visit(~p"/admin/categories/new")
  #     |> assert_a11y()
  #   end
  # end
end
