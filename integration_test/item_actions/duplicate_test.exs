defmodule Backpex.Integration.ItemActions.DuplicateTest do
  use Backpex.ConnCase, async: true

  import Ecto.Query, only: [where: 3]
  import Phoenix.LiveViewTest, only: [render: 1, render_click: 3, render_hook: 3]

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

    test "duplicates the item of the row while another row is selected", %{conn: conn} do
      phoenix = insert(:tag, name: "Phoenix")

      conn
      |> visit(~p"/admin/tags")
      |> check("Select item with id: #{phoenix.id}")
      |> click_button("Duplicate Elixir")
      |> assert_has("#resource-form input[name='change[name]'][value='Elixir']")
      |> submit_duplicate()
      |> assert_has("dd", text: "Elixir", exact: true)

      assert Tag |> where([t], t.name == "Elixir") |> Repo.aggregate(:count) == 2
    end

    test "creates nothing on cancel", %{conn: conn} do
      conn
      |> open_from_index()
      |> cancel()
      |> assert_path(~p"/admin/tags")
      |> assert_has("table tbody tr", count: 1)
    end
  end

  # A row action runs on its row, and the selection of the table is left as it is.
  describe "cancelling on the index view" do
    setup do
      %{phoenix: insert(:tag, name: "Phoenix"), ecto: insert(:tag, name: "Ecto")}
    end

    test "selects nothing if nothing was selected", %{conn: conn, tag: tag} do
      conn
      |> visit(~p"/admin/tags")
      |> click_button("Duplicate Elixir")
      |> assert_has("div", text: "Duplicate", exact: true)
      |> cancel()
      |> refute_has("#select-input-#{tag.id}[checked]")
      |> refute_has("table input[type='checkbox'][checked]")
      |> assert_has("button[phx-value-action-key='delete'][disabled]:not([phx-value-item-id])")
    end

    test "keeps the rows that were selected", %{conn: conn, tag: tag, phoenix: phoenix, ecto: ecto} do
      conn
      |> visit(~p"/admin/tags")
      |> check("Select item with id: #{phoenix.id}")
      |> check("Select item with id: #{ecto.id}")
      |> click_button("Duplicate Elixir")
      |> assert_has("div", text: "Duplicate", exact: true)
      |> assert_has("#select-input-#{phoenix.id}[checked]")
      |> assert_has("#select-input-#{ecto.id}[checked]")
      |> refute_has("#select-input-#{tag.id}[checked]")
      |> cancel()
      |> assert_has("#select-input-#{phoenix.id}[checked]")
      |> assert_has("#select-input-#{ecto.id}[checked]")
      |> refute_has("#select-input-#{tag.id}[checked]")
      |> refute_has("thead input[type='checkbox'][checked]")
      |> refute_has("button[phx-value-action-key='delete'][disabled]:not([phx-value-item-id])")
    end

    test "keeps a selection of all rows", %{conn: conn, tag: tag, phoenix: phoenix, ecto: ecto} do
      conn
      |> visit(~p"/admin/tags")
      |> check("Select all items")
      |> click_button("Duplicate Elixir")
      |> assert_has("div", text: "Duplicate", exact: true)
      |> cancel()
      |> assert_has("thead input[type='checkbox'][checked]")
      |> assert_has("#select-input-#{tag.id}[checked]")
      |> assert_has("#select-input-#{phoenix.id}[checked]")
      |> assert_has("#select-input-#{ecto.id}[checked]")
    end

    test "leaves out a selected row that was deleted while the dialog was open", %{
      conn: conn,
      phoenix: phoenix,
      ecto: ecto
    } do
      session =
        conn
        |> visit(~p"/admin/tags")
        |> check("Select item with id: #{phoenix.id}")
        |> check("Select item with id: #{ecto.id}")
        |> click_button("Duplicate Elixir")
        |> assert_has("div", text: "Duplicate", exact: true)

      Repo.delete!(ecto)

      session
      |> unwrap(fn view ->
        send(view.pid, {"backpex:deleted", ecto})
        render(view)
      end)
      |> cancel()
      |> assert_has("#select-input-#{phoenix.id}[checked]")
      |> refute_has("#select-input-#{ecto.id}")
      |> assert_has("table tbody input[type='checkbox'][checked]", count: 1)
    end

    test "keeps the selection of an action for the selected rows", %{conn: conn, tag: tag, phoenix: phoenix} do
      conn
      |> visit(~p"/admin/tags")
      |> check("Select item with id: #{phoenix.id}")
      # The rows have a "Delete" button, too, so the test sends the event of the one above the table.
      |> unwrap(&render_click(&1, "item-action", %{"action-key" => "delete"}))
      |> assert_has("#action-confirm-modal")
      |> cancel()
      |> assert_has("#select-input-#{phoenix.id}[checked]")
      |> refute_has("#select-input-#{tag.id}[checked]")
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
