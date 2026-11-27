defmodule DemoWeb.Browser.UserBrowserTest do
  use DemoWeb.BrowserCase, async: false
  use DemoWeb, :verified_routes
  use DemoWeb.A11yAssertions

  import Demo.EctoFactory

  @moduletag :playwright

  describe "users index" do
    test "a11y", %{session: session} do
      insert_list(10, :user)

      session
      |> visit(~p"/admin/users")
      |> assert_a11y()
    end

    test "a11y with the multi select of a resource action open", %{session: session} do
      user_options = by_css("input[name='change[users][]']") |> filter(visible: true)

      session
      |> visit(~p"/admin/users/invite/resource-action")
      |> press(by_css("[id^=multi-select-][id$=-trigger]"), "Enter")
      |> assert(count(user_options, 2))
      |> assert_a11y()
    end
  end

  describe "users show" do
    test "a11y", %{session: session} do
      user = insert(:user)

      session
      |> visit(~p"/admin/users/#{user.id}/show")
      |> assert_a11y()
    end
  end

  describe "users edit" do
    test "a11y", %{session: session} do
      user = insert(:user)

      session
      |> visit(~p"/admin/users/#{user.id}/edit")
      |> assert_a11y()
    end
  end

  describe "users new" do
    test "a11y", %{session: session} do
      session
      |> visit(~p"/admin/users/new")
      |> assert_a11y()
    end
  end
end
