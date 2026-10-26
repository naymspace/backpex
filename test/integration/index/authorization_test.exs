defmodule Backpex.Integration.Index.AuthorizationTest do
  use Backpex.ConnCase, async: true

  describe "can?/3 per item" do
    test "hides an item action for the items it is not allowed for", %{conn: conn} do
      user = insert(:user, role: :user)
      admin = insert(:user, role: :admin)

      conn
      |> visit(~p"/admin/users")
      |> assert_has("button[aria-label='Delete'][phx-value-item-id='#{user.id}']")
      |> refute_has("button[aria-label='Delete'][phx-value-item-id='#{admin.id}']")
    end
  end

  # Short links deny `:delete` in `can?/3` but keep the default delete item action.
  describe "can?/3 denying an action" do
    test "hides the item action on the index and the show view", %{conn: conn} do
      short_link = insert(:short_link, short_key: "test123")

      conn
      |> visit(~p"/admin/short-links")
      |> assert_has("#item-action-show-#{short_link.short_key}")
      |> refute_has("button[aria-label='Delete'][phx-value-item-id='#{short_link.short_key}']")

      conn
      |> visit(~p"/admin/short-links/#{short_link.short_key}/show")
      |> assert_has("dd", text: "test123")
      |> assert_has("#item-action-edit")
      |> refute_has("#item-action-delete")
    end
  end

  # Invoices only allow `:index` in `can?/3` and are only routed with `only: [:index]`.
  describe "index-only resource" do
    test "renders neither the new button nor the edit and show item actions", %{conn: conn} do
      invoice = insert(:invoice)

      conn
      |> visit(~p"/admin/invoices")
      |> assert_has("table tbody tr", count: 1)
      |> refute_has("button", text: "New Invoice")
      |> refute_has("#item-action-edit-#{invoice.id}")
      |> refute_has("#item-action-show-#{invoice.id}")
    end
  end
end
