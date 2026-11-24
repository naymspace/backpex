defmodule DemoWeb.Browser.AddressBrowserTest do
  use DemoWeb.BrowserCase, async: false
  use DemoWeb, :verified_routes
  use DemoWeb.A11yAssertions

  import Demo.EctoFactory

  @moduletag :playwright

  describe "addresses index" do
    test "a11y", %{session: session} do
      insert_list(10, :address)

      session
      |> visit(~p"/admin/addresses")
      |> assert_a11y()
    end

    test "delete confirmation modal a11y", %{session: session} do
      address = insert(:address)

      session
      |> visit(~p"/admin/addresses")
      |> click(by_css("#item-action-delete-#{address.id}"))
      |> assert_has(by_css("#action-confirm-modal[open]"))
      |> assert_a11y()
    end
  end

  describe "addresses show" do
    test "a11y", %{session: session} do
      address = insert(:address)

      session
      |> visit(~p"/admin/addresses/#{address.id}/show")
      |> assert_a11y()
    end
  end

  describe "addresses edit" do
    test "a11y", %{session: session} do
      address = insert(:address)

      session
      |> visit(~p"/admin/addresses/#{address.id}/edit")
      |> assert_a11y()
    end
  end

  describe "addresses new" do
    test "a11y", %{session: session} do
      session
      |> visit(~p"/admin/addresses/new")
      |> assert_a11y()
    end
  end
end
