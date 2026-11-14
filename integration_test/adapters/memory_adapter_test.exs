defmodule Backpex.Integration.Adapters.MemoryAdapterTest do
  @moduledoc """
  Runs the adapter conformance tests against `Backpex.Adapters.Memory` and drives `Backpex.Test.MemoryNoteLive`. The
  adapter runs no part of a query, so these tests check that Backpex applies every part in memory. The notes live in
  one store, so the tests are not async.
  """

  use Backpex.ConnCase, async: false

  alias Backpex.Adapters.Memory
  alias Backpex.Test.MemoryNote
  alias Backpex.Test.MemoryNoteLive
  alias Backpex.Test.MemoryNotes

  @store MemoryNotes

  defmodule Conformance do
    use ExUnit.Case, async: false
    use Backpex.Test.AdapterConformance, live_resource: MemoryNoteLive, field: :title, nullable_field: :likes

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

  describe "insert/2 and update/2" do
    defmodule Country do
      use Ecto.Schema

      @primary_key {:code, :string, autogenerate: false}
      embedded_schema do
        field :name, :string
      end
    end

    defmodule CountryLive do
      def config(:primary_key), do: :code
      def adapter_config(:schema), do: Country
      def adapter_config(:store), do: MemoryNotes
    end

    defp change_note(note, attrs), do: Ecto.Changeset.cast(note, attrs, [:id, :title, :likes])

    test "insert/2 refuses a primary key another item has" do
      assert {:error, changeset} =
               %MemoryNote{} |> change_note(%{id: 1, title: "Copy"}) |> Memory.insert(MemoryNoteLive)

      assert %{action: :insert, errors: [id: {"has already been taken", [constraint: :unique]}]} = changeset
      assert @store |> Memory.items() |> Enum.map(&{&1.id, &1.title}) |> Enum.take(2) == [{1, "Bravo"}, {2, "alpha"}]
      assert length(Memory.items(@store)) == 4
    end

    test "insert/2 generates the next integer and keeps a given primary key" do
      assert {:ok, %MemoryNote{id: 5}} = %MemoryNote{} |> change_note(%{title: "Next"}) |> Memory.insert(MemoryNoteLive)
      assert {:ok, %MemoryNote{id: 9}} = %MemoryNote{} |> change_note(%{id: 9}) |> Memory.insert(MemoryNoteLive)
    end

    test "insert/2 raises for a missing primary key of a type it can't generate and keeps the store" do
      Memory.put_items(@store, [%Country{code: "DE", name: "Germany"}])

      assert_raise ArgumentError, ~r/can't generate the primary key :code of .*Country, as its type is :string/, fn ->
        %Country{} |> Ecto.Changeset.cast(%{name: "France"}, [:name]) |> Memory.insert(CountryLive)
      end

      assert {:ok, %Country{code: "FR"}} =
               %Country{}
               |> Ecto.Changeset.cast(%{code: "FR", name: "France"}, [:code, :name])
               |> Memory.insert(CountryLive)

      assert @store |> Memory.items() |> Enum.map(& &1.code) == ~w(DE FR)
    end

    test "update/2 replaces the item with the primary key it had before the change" do
      [bravo | _notes] = Memory.items(@store)

      assert {:ok, %MemoryNote{id: 7, title: "Moved"}} =
               bravo |> change_note(%{id: 7, title: "Moved"}) |> Memory.update(MemoryNoteLive)

      assert @store |> Memory.items() |> Enum.map(&{&1.id, &1.title}) |> hd() == {7, "Moved"}
      assert length(Memory.items(@store)) == 4
    end

    test "update/2 refuses a change to the primary key of another item" do
      [bravo | _notes] = Memory.items(@store)

      assert {:error, changeset} = bravo |> change_note(%{id: 2}) |> Memory.update(MemoryNoteLive)

      assert %{action: :update, errors: [id: {"has already been taken", [constraint: :unique]}]} = changeset
      assert @store |> Memory.items() |> Enum.map(& &1.id) == [1, 2, 3, 4]
    end
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

  test "update_all/3 changes the stored items, not the given ones" do
    stale = %MemoryNote{id: 1, title: "Stale title", likes: 0}

    assert Memory.update_all([stale], %{likes: 7}, MemoryNoteLive) == {:ok, 1}
    assert %MemoryNote{title: "Bravo", likes: 7} = @store |> Memory.items() |> Enum.find(&(&1.id == 1))
  end
end
