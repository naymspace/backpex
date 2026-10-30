defmodule Backpex.Integration.Options.AdapterTest do
  @moduledoc """
  Checks that the views of a LiveResource read and write through the adapter of its `adapter` option.
  `Backpex.Test.RecordingNoteLive` uses `Backpex.Test.RecordingAdapter`, which delegates to `Backpex.Adapters.Ecto` and
  reports each call.
  """
  use Backpex.ConnCase, async: true

  alias Backpex.Test.Note
  alias Backpex.Test.RecordingAdapter
  alias Backpex.Test.RecordingNoteLive

  setup do
    test_pid = self()
    handler_id = {__MODULE__, make_ref()}

    # Only the calls of this test's processes (a dead render runs in the test process, a LiveView has it in its
    # `$callers`) are forwarded, so async tests don't see each other's calls.
    :telemetry.attach(
      handler_id,
      RecordingAdapter.event(),
      fn _event, _measurements, metadata, _config ->
        if test_pid in [metadata.pid | metadata.callers] do
          send(test_pid, {:adapter_call, metadata.function, metadata.live_resource})
        end
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end

  test "the index view lists and counts the items through the adapter", %{conn: conn} do
    insert(:note, title: "Listed note")

    conn
    |> visit(~p"/admin/recording-notes")
    |> assert_has("td", text: "Listed note")

    assert_received {:adapter_call, :read, RecordingNoteLive}
    assert_received {:adapter_call, :count, RecordingNoteLive}
  end

  test "the show view gets the item through the adapter", %{conn: conn} do
    note = insert(:note, title: "Shown note")

    conn
    |> visit(~p"/admin/recording-notes/#{note.id}/show")
    |> assert_has("dd", text: "Shown note")

    assert_received {:adapter_call, :read, RecordingNoteLive}
  end

  test "the form view changes and inserts a new item through the adapter", %{conn: conn} do
    conn
    |> visit(~p"/admin/recording-notes/new")
    |> fill_in("Title", with: "Created note")
    |> click_button("Save")
    |> assert_path(~p"/admin/recording-notes")

    assert_received {:adapter_call, :change, RecordingNoteLive}
    assert_received {:adapter_call, :insert, RecordingNoteLive}
    assert Repo.get_by(Note, title: "Created note")
  end

  test "the form view gets and updates the item through the adapter", %{conn: conn} do
    note = insert(:note, title: "Old title")

    conn
    |> visit(~p"/admin/recording-notes/#{note.id}/edit")
    |> fill_in("Title", with: "New title")
    |> click_button("Save")
    |> assert_path(~p"/admin/recording-notes")

    assert_received {:adapter_call, :read, RecordingNoteLive}
    assert_received {:adapter_call, :update, RecordingNoteLive}
    assert Repo.get!(Note, note.id).title == "New title"
  end

  test "the delete item action deletes the item through the adapter", %{conn: conn} do
    note = insert(:note, title: "Deleted note")

    conn
    |> visit(~p"/admin/recording-notes")
    |> within("table", &click_button(&1, "Delete"))
    |> within("#resource-form", &click_button(&1, "Delete"))
    |> refute_has("td", text: "Deleted note")

    assert_received {:adapter_call, :delete_all, RecordingNoteLive}
    refute Repo.get(Note, note.id)
  end
end
