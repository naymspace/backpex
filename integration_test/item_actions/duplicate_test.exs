defmodule Backpex.Integration.ItemActions.DuplicateTest do
  use Backpex.ConnCase, async: true

  import Ecto.Query, only: [where: 3]
  import Phoenix.LiveViewTest

  alias Backpex.Test.Tag

  setup do
    %{tag: insert(:tag, name: "Elixir")}
  end

  describe "on the index view" do
    test "duplicates the item with the values of the original", %{conn: conn, tag: tag} do
      conn
      |> open_from_index(tag)
      |> submit_duplicate()
      |> assert_path(~p"/admin/tags/#{copy_of(tag).id}/show")
      |> assert_has("dd", text: "Elixir", exact: true)
    end

    test "duplicates the item with changed values", %{conn: conn, tag: tag} do
      conn
      |> open_from_index(tag)
      |> submit_duplicate(%{name: "Elixir Copy"})
      |> assert_path(~p"/admin/tags/#{copy_of(tag).id}/show")
      |> assert_has("dd", text: "Elixir Copy", exact: true)
    end

    test "creates nothing on cancel", %{conn: conn, tag: tag} do
      conn
      |> open_from_index(tag)
      |> unwrap(&render_hook(&1, "cancel-action-confirm", %{}))
      |> assert_path(~p"/admin/tags")
      |> assert_has("table tbody tr", count: 1)
    end
  end

  describe "on the show view" do
    test "duplicates the item with the values of the original", %{conn: conn, tag: tag} do
      conn
      |> open_from_show(tag)
      |> submit_duplicate()
      |> assert_path(~p"/admin/tags/#{copy_of(tag).id}/show")
      |> assert_has("dd", text: "Elixir", exact: true)
    end

    test "duplicates the item with changed values", %{conn: conn, tag: tag} do
      conn
      |> open_from_show(tag)
      |> submit_duplicate(%{name: "Elixir Copy"})
      |> assert_path(~p"/admin/tags/#{copy_of(tag).id}/show")
      |> assert_has("dd", text: "Elixir Copy", exact: true)
    end

    test "creates nothing on cancel", %{conn: conn, tag: tag} do
      conn
      |> open_from_show(tag)
      |> unwrap(&render_hook(&1, "cancel-action-confirm", %{}))
      |> assert_path(~p"/admin/tags/#{tag.id}/show")
      |> assert_has("dd", text: "Elixir", exact: true)

      assert Repo.aggregate(Tag, :count) == 1
    end
  end

  defp open_from_index(conn, tag) do
    conn
    |> visit(~p"/admin/tags")
    |> assert_has("table tbody tr", count: 1)
    |> unwrap(fn view -> view |> element("#item-action-duplicate-#{tag.id}") |> render_click() end)
    |> assert_has("div", text: "Duplicate", exact: true)
  end

  defp open_from_show(conn, tag) do
    conn
    |> visit(~p"/admin/tags/#{tag.id}/show")
    |> unwrap(fn view -> view |> element("#item-action-duplicate") |> render_click() end)
    |> assert_has("div", text: "Duplicate", exact: true)
  end

  defp submit_duplicate(session, change \\ %{}) do
    unwrap(session, fn view -> view |> form("#resource-form", change: change) |> render_submit() end)
  end

  # The action opens the copy it created, so the tests look it up after the submit.
  defp copy_of(tag) do
    Tag |> where([t], t.id != ^tag.id) |> Repo.one!()
  end
end
