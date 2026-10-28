defmodule Backpex.Integration.Adapters.MemoryAdapterTest do
  @moduledoc """
  Runs the adapter conformance tests against `Backpex.Adapters.Memory` and drives `Backpex.Test.MemoryNoteLive`. The
  adapter runs no part of a query, so these tests check that Backpex applies every part in memory. The notes live in
  one store, so the tests are not async.
  """

  use Backpex.ConnCase, async: false

  alias Backpex.Adapters.Memory
  alias Backpex.Test.MemoryNote
  alias Backpex.Test.MemoryNotes

  @store MemoryNotes

  defmodule Conformance do
    use ExUnit.Case, async: false
    use Backpex.Test.AdapterConformance, live_resource: Backpex.Test.MemoryNoteLive, field: :title

    setup do
      Memory.put_items(MemoryNotes, [])
    end

    def insert_item(attrs) do
      note = struct(MemoryNote, Map.put(attrs, :id, System.unique_integer([:positive])))
      Memory.put_items(MemoryNotes, Enum.concat(Memory.items(MemoryNotes), [note]))

      note
    end

    def new_item, do: %MemoryNote{}
  end

  setup do
    Memory.put_items(@store, [
      %MemoryNote{id: 1, title: "Bravo", likes: 2},
      %MemoryNote{id: 2, title: "alpha", likes: nil},
      %MemoryNote{id: 3, title: "Charlie", likes: 5},
      %MemoryNote{id: 4, title: "Secret note", likes: 100}
    ])
  end

  test "the index view sorts, searches, scopes and aggregates the notes in memory", %{conn: conn} do
    conn
    |> visit(~p"/admin/memory-notes")
    # Strings sort by their code points in memory, so upper case comes first.
    |> assert_rows("table tbody", ~w(Bravo Charlie alpha))
    |> refute_has("td", text: "Secret note")
    |> assert_has("p", text: "7 likes")

    conn
    |> visit(~p"/admin/memory-notes?#{%{order_by: "likes", order_direction: "desc"}}")
    |> assert_rows("table tbody", ~w(alpha Charlie Bravo))

    conn
    |> visit(~p"/admin/memory-notes?#{%{search: "ALP"}}")
    |> assert_rows("table tbody", ~w(alpha))
  end

  test "the show view finds a note in the scope only", %{conn: conn} do
    conn
    |> visit(~p"/admin/memory-notes/3/show")
    |> assert_has("dd", text: "Charlie")

    assert_error_sent 404, fn -> get(conn, ~p"/admin/memory-notes/4/show") end
    assert_error_sent 404, fn -> get(conn, ~p"/admin/memory-notes/not-a-number/show") end
  end

  test "the form view creates and updates notes in the store", %{conn: conn} do
    conn
    |> visit(~p"/admin/memory-notes/new")
    |> fill_in("Title", with: "Delta")
    |> click_button("Save")
    |> assert_path(~p"/admin/memory-notes")
    |> assert_has("td", text: "Delta")

    conn
    |> visit(~p"/admin/memory-notes/1/edit")
    |> fill_in("Title", with: "Bravo edited")
    |> click_button("Save")
    |> assert_has("td", text: "Bravo edited")

    assert %MemoryNote{id: 5, title: "Delta"} = @store |> Memory.items() |> Enum.find(&(&1.title == "Delta"))
  end

  test "the delete item action removes the note from the store", %{conn: conn} do
    conn
    |> visit(~p"/admin/memory-notes")
    |> within("table tbody tr:nth-child(1)", &click_button(&1, "Delete"))
    |> within("#resource-form", &click_button(&1, "Delete"))
    |> refute_has("td", text: "Bravo")

    refute @store |> Memory.items() |> Enum.any?(&(&1.id == 1))
  end

  test "the views hide the writes an adapter doesn't support and refuse them", %{conn: conn} do
    conn
    |> visit(~p"/admin/read-only-notes")
    |> assert_rows("table tbody", ["Bravo", "alpha", "Charlie", "Secret note"])
    |> refute_has("a", text: "New Note")
    |> refute_has("button[aria-label=Delete]")
    |> refute_has("a[aria-label=Edit]")
    |> assert_has("a[aria-label=Show]")

    assert_error_sent 403, fn -> get(conn, ~p"/admin/read-only-notes/new") end
    assert_error_sent 403, fn -> get(conn, ~p"/admin/read-only-notes/1/edit") end
  end
end
