defmodule Backpex.Integration.ItemActions.DuplicateTest do
  use Backpex.ConnCase, async: true

  import Ecto.Query, only: [where: 3]
  import Phoenix.LiveViewTest, only: [render_hook: 3]

  alias Backpex.Test.Tag

  setup do
    %{tag: insert(:tag, name: "Elixir")}
  end

  describe "on the index view" do
    test "duplicates the item with the values of the original", %{conn: conn, tag: tag} do
      conn
      |> open_from_index()
      |> submit_duplicate()
      |> assert_path(~p"/admin/tags/#{copy_of(tag).id}/show")
      |> assert_has("dd", text: "Elixir", exact: true)
    end

    test "duplicates the item with changed values", %{conn: conn, tag: tag} do
      conn
      |> open_from_index()
      |> submit_duplicate("Elixir Copy")
      |> assert_path(~p"/admin/tags/#{copy_of(tag).id}/show")
      |> assert_has("dd", text: "Elixir Copy", exact: true)
    end

    test "creates nothing on cancel", %{conn: conn} do
      conn
      |> open_from_index()
      |> cancel()
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
      |> submit_duplicate("Elixir Copy")
      |> assert_path(~p"/admin/tags/#{copy_of(tag).id}/show")
      |> assert_has("dd", text: "Elixir Copy", exact: true)
    end

    test "creates nothing on cancel", %{conn: conn, tag: tag} do
      conn
      |> open_from_show(tag)
      |> cancel()
      |> assert_path(~p"/admin/tags/#{tag.id}/show")
      |> assert_has("dd", text: "Elixir", exact: true)

      assert Repo.aggregate(Tag, :count) == 1
    end
  end

  defp open_from_index(conn) do
    conn
    |> visit(~p"/admin/tags")
    |> assert_has("table tbody tr", count: 1)
    |> click_button("Duplicate Elixir")
    |> assert_has("div", text: "Duplicate", exact: true)
  end

  defp open_from_show(conn, tag) do
    conn
    |> visit(~p"/admin/tags/#{tag.id}/show")
    |> click_button("Duplicate Elixir")
    |> assert_has("div", text: "Duplicate", exact: true)
  end

  defp submit_duplicate(session), do: within(session, "#resource-form", &click_button(&1, "Duplicate"))

  defp submit_duplicate(session, name) do
    session
    |> within("#resource-form", &fill_in(&1, "Name", with: name))
    |> submit_duplicate()
  end

  # The cancel button and the close button of the dialog push the event through `JS.exec/2`, which phoenix_test can't
  # run, so the test sends the event of the dialog's `data-cancel` attribute.
  defp cancel(session) do
    unwrap(session, &render_hook(&1, "cancel-action-confirm", %{}))
  end

  # The action opens the copy it created, so the tests look it up after the submit.
  defp copy_of(tag) do
    Tag |> where([t], t.id != ^tag.id) |> Repo.one!()
  end
end
