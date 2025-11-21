defmodule DemoWeb.Browser.AddressBrowserTest do
  use PhoenixTest.Playwright.Case, async: false
  use DemoWeb, :verified_routes
  use DemoWeb.A11yAssertions

  import Demo.EctoFactory

  @moduletag :playwright

  describe "addresses index" do
    test "a11y", %{conn: conn} do
      insert_list(10, :address)

      conn
      |> visit(~p"/admin/addresses")
      |> assert_a11y()
    end
  end

  describe "addresses show" do
    test "a11y", %{conn: conn} do
      address = insert(:address)

      conn
      |> visit(~p"/admin/addresses/#{address.id}/show")
      |> assert_a11y()
    end
  end

  describe "addresses edit" do
    test "a11y", %{conn: conn} do
      address = insert(:address)

      conn
      |> visit(~p"/admin/addresses/#{address.id}/edit")
      |> assert_a11y()
    end
  end

  describe "addresses new" do
    test "a11y", %{conn: conn} do
      conn
      |> visit(~p"/admin/addresses/new")
      |> assert_a11y()
    end
  end
end
