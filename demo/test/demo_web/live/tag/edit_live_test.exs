defmodule DemoWeb.Live.Tag.EditLiveTest do
  use DemoWeb.ConnCase, async: false

  import Demo.EctoFactory
  import Phoenix.LiveViewTest

  describe "tags live resource edit" do
    test "is rendered", %{conn: conn} do
      tag = insert(:tag)

      conn
      |> visit(~p"/admin/tags/#{tag.id}/edit")
      |> assert_has("h1", text: "Edit Tag", exact: true)
      |> assert_has("button", text: "Cancel", exact: true)
      |> assert_has("button", text: "Save", exact: true)
    end

    test "submit form", %{conn: conn} do
      tag = insert(:tag, %{name: "Elixir"})

      conn
      |> visit(~p"/admin/tags/#{tag.id}/edit")
      |> unwrap(fn view ->
        view
        |> form("#resource-form", change: %{name: "Phoenix"})
        |> put_submitter("button[value=save]")
        |> render_submit()
      end)
      |> assert_has("table tbody tr", count: 1)
      |> assert_has("p", text: "Phoenix", exact: true)
    end

    test "editing with invalid data shows error", %{conn: conn} do
      tag = insert(:tag, %{name: "Elixir"})

      conn
      |> visit(~p"/admin/tags/#{tag.id}/edit")
      |> unwrap(fn view ->
        view
        |> form("#resource-form", change: %{name: ""})
        |> put_submitter("button[value=save]")
        |> render_submit()
      end)
      |> assert_has("form#resource-form")
      |> assert_has("p", text: "can't be blank")
    end
  end
end
