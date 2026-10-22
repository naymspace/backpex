defmodule DemoWeb.Browser.UserBrowserTest do
  use PhoenixTest.Playwright.Case, async: false
  use DemoWeb, :verified_routes
  use DemoWeb.A11yAssertions

  import Demo.EctoFactory

  @moduletag :playwright

  describe "users index" do
    test "a11y", %{conn: conn} do
      insert_list(10, :user)

      conn
      |> visit(~p"/admin/users")
      |> assert_a11y()
    end

    test "a11y with the multi select of a resource action open", %{conn: conn} do
      conn
      |> visit(~p"/admin/users/invite/resource-action")
      |> assert_has("body .phx-connected")
      |> press("[id^=multi-select-][id$=-trigger]", "Enter")
      |> assert_has("input[name='change[users][]']", count: 2)
      |> assert_a11y()
    end
  end

  describe "users show" do
    test "a11y", %{conn: conn} do
      user = insert(:user)

      conn
      |> visit(~p"/admin/users/#{user.id}/show")
      |> assert_a11y()
    end
  end

  describe "users edit" do
    test "a11y", %{conn: conn} do
      user = insert(:user)

      conn
      |> visit(~p"/admin/users/#{user.id}/edit")
      |> assert_a11y()
    end
  end

  describe "users new" do
    test "a11y", %{conn: conn} do
      conn
      |> visit(~p"/admin/users/new")
      |> assert_a11y()
    end
  end
end
