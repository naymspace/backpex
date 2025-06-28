defmodule DemoWeb.Browser.ShortLinkBrowserTest do
  use PhoenixTest.Playwright.Case, async: false
  use DemoWeb, :verified_routes
  use DemoWeb.A11yAssertions

  import Demo.EctoFactory

  @moduletag :playwright

  describe "short-links index" do
    test "a11y", %{conn: conn} do
      insert_list(10, :short_link)

      conn
      |> visit(~p"/admin/short-links")
      |> assert_a11y()
    end
  end

  describe "short-links show" do
    test "a11y", %{conn: conn} do
      short_link = insert(:short_link)

      conn
      |> visit(~p"/admin/short-links/#{short_link.short_key}/show")
      |> assert_a11y()
    end
  end

  describe "short-links edit" do
    test "a11y", %{conn: conn} do
      short_link = insert(:short_link)

      conn
      |> visit(~p"/admin/short-links/#{short_link.short_key}/edit")
      |> assert_a11y()
    end
  end

  describe "short-links new" do
    test "a11y", %{conn: conn} do
      conn
      |> visit(~p"/admin/short-links/new")
      |> assert_a11y()
    end
  end
end
