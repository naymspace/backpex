defmodule DemoWeb.Live.Tag.DuplicateItemActionLiveTest do
  use DemoWeb.ConnCase, async: false

  import Demo.EctoFactory
  import Ecto.Query, only: [where: 3]
  import Phoenix.LiveViewTest

  describe "duplicate item action on index view" do
    test "duplicates item successfully with original name", %{conn: conn} do
      tag = insert(:tag, name: "Elixir")

      conn
      |> visit(~p"/admin/tags")
      |> assert_has("td", text: tag.name, exact: true)
      |> unwrap(fn view ->
        view
        |> element("#item-action-duplicate-#{tag.id}")
        |> render_click()
      end)
      |> assert_has("div", text: "Duplicate", exact: true)
      |> unwrap(fn view ->
        view
        |> form("#resource-form")
        |> render_submit()
      end)
      |> assert_path(~p"/admin/tags/#{copy_of(tag).id}/show")
      |> assert_has("dd", text: tag.name, exact: true)
    end

    test "duplicates item successfully with modified name", %{conn: conn} do
      tag = insert(:tag, name: "Elixir")

      conn
      |> visit(~p"/admin/tags")
      |> assert_has("td", text: tag.name, exact: true)
      |> unwrap(fn view ->
        view
        |> element("#item-action-duplicate-#{tag.id}")
        |> render_click()
      end)
      |> assert_has("div", text: "Duplicate", exact: true)
      |> unwrap(fn view ->
        view
        |> form("#resource-form", change: %{name: "Elixir Copy"})
        |> render_submit()
      end)
      |> assert_path(~p"/admin/tags/#{copy_of(tag).id}/show")
      |> assert_has("dd", text: "Elixir Copy", exact: true)
    end

    test "cancels duplicate action", %{conn: conn} do
      tag = insert(:tag, name: "Elixir")

      conn
      |> visit(~p"/admin/tags")
      |> assert_has("td", text: tag.name, exact: true)
      |> assert_has("table tbody tr", count: 1)
      |> unwrap(fn view ->
        view
        |> element("#item-action-duplicate-#{tag.id}")
        |> render_click()
      end)
      |> assert_has("div", text: "Duplicate", exact: true)
      |> unwrap(fn view ->
        render_hook(view, "cancel-action-confirm", %{})
      end)
      |> assert_path(~p"/admin/tags")
      |> assert_has("table tbody tr", count: 1)
    end
  end

  describe "duplicate item action on show view" do
    test "duplicates item successfully with original name", %{conn: conn} do
      tag = insert(:tag, name: "Phoenix")

      conn
      |> visit(~p"/admin/tags/#{tag.id}/show")
      |> assert_has("dd", text: tag.name, exact: true)
      |> assert_has("#item-action-duplicate")
      |> unwrap(fn view ->
        view
        |> element("#item-action-duplicate")
        |> render_click()
      end)
      |> assert_has("div", text: "Duplicate", exact: true)
      |> unwrap(fn view ->
        view
        |> form("#resource-form")
        |> render_submit()
      end)
      |> assert_path(~p"/admin/tags/#{copy_of(tag).id}/show")
      |> assert_has("dd", text: tag.name, exact: true)
    end

    test "duplicates item successfully with modified name", %{conn: conn} do
      tag = insert(:tag, name: "Phoenix")

      conn
      |> visit(~p"/admin/tags/#{tag.id}/show")
      |> assert_has("dd", text: tag.name, exact: true)
      |> assert_has("#item-action-duplicate")
      |> unwrap(fn view ->
        view
        |> element("#item-action-duplicate")
        |> render_click()
      end)
      |> assert_has("div", text: "Duplicate", exact: true)
      |> unwrap(fn view ->
        view
        |> form("#resource-form", change: %{name: "Phoenix Copy"})
        |> render_submit()
      end)
      |> assert_path(~p"/admin/tags/#{copy_of(tag).id}/show")
      |> assert_has("dd", text: "Phoenix Copy", exact: true)
    end

    test "cancels duplicate action", %{conn: conn} do
      tag = insert(:tag, name: "Phoenix")

      conn
      |> visit(~p"/admin/tags/#{tag.id}/show")
      |> assert_has("dd", text: tag.name, exact: true)
      |> assert_has("#item-action-duplicate")
      |> unwrap(fn view ->
        view
        |> element("#item-action-duplicate")
        |> render_click()
      end)
      |> assert_has("div", text: "Duplicate", exact: true)
      |> unwrap(fn view ->
        render_hook(view, "cancel-action-confirm", %{})
      end)
      |> assert_path(~p"/admin/tags/#{tag.id}/show")
      |> assert_has("dd", text: tag.name, exact: true)
    end
  end

  # The action opens the copy it created, so the tests look it up after the submit.
  defp copy_of(tag) do
    Demo.Tag |> where([t], t.id != ^tag.id) |> Demo.Repo.one!()
  end
end
