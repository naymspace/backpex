defmodule DemoWeb.Live.Tag.OpenItemActionFromUrlLiveTest do
  use DemoWeb.ConnCase, async: false

  import Demo.EctoFactory
  import Phoenix.LiveViewTest

  describe "item_action query param on the show view" do
    test "opens the confirmation dialog of the action", %{conn: conn} do
      tag = insert(:tag, name: "Elixir")

      conn
      |> visit(~p"/admin/tags/#{tag.id}/show?item_action=duplicate")
      |> assert_has("form#resource-form")
      |> unwrap(fn view ->
        view
        |> form("#resource-form", change: %{name: "Elixir Copy"})
        |> render_submit()
      end)
      |> assert_has("dd", text: "Elixir Copy", exact: true)
    end

    test "ignores an unknown action", %{conn: conn} do
      tag = insert(:tag, name: "Elixir")

      conn
      |> visit(~p"/admin/tags/#{tag.id}/show?item_action=unknown")
      |> assert_has("dd", text: "Elixir", exact: true)
      |> refute_has("form#resource-form")
    end

    test "never runs an action without a confirmation dialog", %{conn: conn} do
      tag = insert(:tag, name: "Elixir")

      conn
      |> visit(~p"/admin/tags/#{tag.id}/show?item_action=edit")
      |> assert_path(~p"/admin/tags/#{tag.id}/show")
      |> refute_has("form#resource-form")
    end
  end
end
