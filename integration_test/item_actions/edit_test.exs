defmodule Backpex.Integration.ItemActions.EditTest do
  use Backpex.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup do
    %{tag: insert(:tag, name: "Elixir")}
  end

  describe "on the index view" do
    test "saves the item and returns to the index view", %{conn: conn, tag: tag} do
      conn
      |> visit(~p"/admin/tags")
      |> assert_has("td", text: "Elixir", exact: true)
      |> click_item_action("#item-action-edit-#{tag.id}")
      |> assert_path(~p"/admin/tags/#{tag.id}/edit")
      |> submit_name("Updated Elixir")
      |> assert_path(~p"/admin/tags")
      |> assert_has("td", text: "Updated Elixir", exact: true)
    end

    test "returns to the index view on cancel", %{conn: conn, tag: tag} do
      conn
      |> visit(~p"/admin/tags")
      |> click_item_action("#item-action-edit-#{tag.id}")
      |> assert_path(~p"/admin/tags/#{tag.id}/edit")
      |> cancel()
      |> assert_path(~p"/admin/tags")
      |> assert_has("td", text: "Elixir", exact: true)
    end
  end

  describe "on the show view" do
    test "saves the item and returns to the show view", %{conn: conn, tag: tag} do
      conn
      |> visit(~p"/admin/tags/#{tag.id}/show")
      |> assert_has("dd", text: "Elixir", exact: true)
      |> click_item_action("#item-action-edit")
      |> assert_path(~p"/admin/tags/#{tag.id}/edit")
      |> submit_name("Updated Elixir")
      |> assert_path(~p"/admin/tags/#{tag.id}/show")
      |> assert_has("dd", text: "Updated Elixir", exact: true)
    end

    test "returns to the show view on cancel", %{conn: conn, tag: tag} do
      conn
      |> visit(~p"/admin/tags/#{tag.id}/show")
      |> click_item_action("#item-action-edit")
      |> assert_path(~p"/admin/tags/#{tag.id}/edit")
      |> cancel()
      |> assert_path(~p"/admin/tags/#{tag.id}/show")
      |> assert_has("dd", text: "Elixir", exact: true)
    end
  end

  defp click_item_action(session, selector) do
    unwrap(session, fn view -> view |> element(selector) |> render_click() end)
  end

  defp submit_name(session, name) do
    unwrap(session, fn view ->
      view
      |> form("#resource-form", change: %{name: name})
      |> put_submitter("button[value=save]")
      |> render_submit()
    end)
  end

  defp cancel(session) do
    unwrap(session, fn view -> view |> element("a:has(button[value='cancel'])") |> render_click() end)
  end
end
