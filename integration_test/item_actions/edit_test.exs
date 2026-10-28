defmodule Backpex.Integration.ItemActions.EditTest do
  use Backpex.ConnCase, async: true

  setup do
    %{tag: insert(:tag, name: "Elixir")}
  end

  describe "on the index view" do
    test "saves the item and returns to the index view", %{conn: conn, tag: tag} do
      conn
      |> visit(~p"/admin/tags")
      |> assert_has("td", text: "Elixir", exact: true)
      |> click_link("Edit")
      |> assert_path(~p"/admin/tags/#{tag.id}/edit")
      |> submit_name("Updated Elixir")
      |> assert_path(~p"/admin/tags")
      |> assert_has("td", text: "Updated Elixir", exact: true)
    end

    test "returns to the index view on cancel", %{conn: conn, tag: tag} do
      conn
      |> visit(~p"/admin/tags")
      |> click_link("Edit")
      |> assert_path(~p"/admin/tags/#{tag.id}/edit")
      |> click_link("Cancel")
      |> assert_path(~p"/admin/tags")
      |> assert_has("td", text: "Elixir", exact: true)
    end
  end

  describe "on the show view" do
    test "saves the item and returns to the show view", %{conn: conn, tag: tag} do
      conn
      |> visit(~p"/admin/tags/#{tag.id}/show")
      |> assert_has("dd", text: "Elixir", exact: true)
      |> click_link("Edit")
      |> assert_path(~p"/admin/tags/#{tag.id}/edit")
      |> submit_name("Updated Elixir")
      |> assert_path(~p"/admin/tags/#{tag.id}/show")
      |> assert_has("dd", text: "Updated Elixir", exact: true)
    end

    test "returns to the show view on cancel", %{conn: conn, tag: tag} do
      conn
      |> visit(~p"/admin/tags/#{tag.id}/show")
      |> click_link("Edit")
      |> assert_path(~p"/admin/tags/#{tag.id}/edit")
      |> click_link("Cancel")
      |> assert_path(~p"/admin/tags/#{tag.id}/show")
      |> assert_has("dd", text: "Elixir", exact: true)
    end
  end

  defp submit_name(session, name) do
    session
    |> fill_in("Name", with: name)
    |> click_button("Save")
  end
end
