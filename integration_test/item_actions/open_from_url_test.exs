defmodule Backpex.Integration.ItemActions.OpenFromUrlTest do
  use Backpex.ConnCase, async: true

  setup do
    %{tag: insert(:tag, name: "Elixir")}
  end

  describe "item_action query param on the show view" do
    test "opens the confirmation dialog of the action", %{conn: conn, tag: tag} do
      conn
      |> visit(~p"/admin/tags/#{tag.id}/show?item_action=duplicate")
      |> assert_has("form#resource-form")
      |> within("#resource-form", fn session ->
        session
        |> fill_in("Name", with: "Elixir Copy")
        |> click_button("Duplicate")
      end)
      |> assert_has("dd", text: "Elixir Copy", exact: true)
    end

    test "ignores an unknown action", %{conn: conn, tag: tag} do
      conn
      |> visit(~p"/admin/tags/#{tag.id}/show?item_action=unknown")
      |> assert_has("dd", text: "Elixir", exact: true)
      |> refute_has("form#resource-form")
    end

    test "never runs an action without a confirmation dialog", %{conn: conn, tag: tag} do
      conn
      |> visit(~p"/admin/tags/#{tag.id}/show?item_action=edit")
      |> assert_path(~p"/admin/tags/#{tag.id}/show")
      |> refute_has("form#resource-form")
    end
  end
end
