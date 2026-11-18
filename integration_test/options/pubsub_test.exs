defmodule Backpex.Integration.Options.PubSubTest do
  @moduledoc """
  Checks the `pubsub` option: `Backpex.Test.PubSubNoteLive` broadcasts its events on the configured server and topic,
  and its index view reloads on events of that topic only. Also checks which adapter calls the index and show views make
  for a `"backpex:updated"` event, with `Backpex.Test.RecordingNoteLive`.
  """
  use Backpex.ConnCase, async: true

  import Phoenix.LiveViewTest, only: [live: 2, render: 1]

  alias Backpex.Test.Note
  alias Backpex.Test.PubSubNoteLive
  alias Backpex.Test.RecordingAdapter

  @server Backpex.Test.OptionsPubSub
  @topic "options-notes"

  setup do
    :ok = Phoenix.PubSub.subscribe(@server, @topic)
  end

  describe "broadcasts on the configured server and topic" do
    test "when an item is created", %{conn: conn} do
      conn
      |> visit(~p"/admin/pubsub-notes/new")
      |> fill_in("Title", with: "Created note")
      |> click_button("Save")
      |> assert_path(~p"/admin/pubsub-notes")

      assert_received {"created", %Note{title: "Created note"}}
      assert_received {"backpex:created", %Note{title: "Created note"}}
    end

    test "when an item is updated", %{conn: conn} do
      note = insert(:note, title: "Old title")

      conn
      |> visit(~p"/admin/pubsub-notes/#{note.id}/edit")
      |> fill_in("Title", with: "New title")
      |> click_button("Save")
      |> assert_path(~p"/admin/pubsub-notes")

      assert_received {"updated", %Note{id: id, title: "New title"}} when id == note.id
      assert_received {"backpex:updated", %Note{id: id, title: "New title"}} when id == note.id
    end

    test "when an item is deleted", %{conn: conn} do
      note = insert(:note, title: "Deleted note")

      conn
      |> visit(~p"/admin/pubsub-notes")
      |> within("table", &click_button(&1, "Delete"))
      |> within("#resource-form", &click_button(&1, "Delete"))
      |> refute_has("td", text: "Deleted note")

      assert_received {"deleted", %Note{id: id}} when id == note.id
      assert_received {"backpex:deleted", %Note{id: id}} when id == note.id
    end
  end

  test "the index view reloads on events of the configured topic, not of the default one", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/pubsub-notes")
    note = insert(:note, title: "Inserted behind the view")

    # The server and topic the LiveResource would use without the option. `Phoenix.PubSub.broadcast/3` dispatches from
    # this process, so the event arrives before the render call.
    Phoenix.PubSub.broadcast(Backpex.Test.AppPubSub, to_string(PubSubNoteLive), {"backpex:created", note})
    refute render(view) =~ "Inserted behind the view"

    Phoenix.PubSub.broadcast(@server, @topic, {"backpex:created", note})
    assert render(view) =~ "Inserted behind the view"
  end

  describe "an updated event" do
    setup do
      test_pid = self()
      handler_id = {__MODULE__, make_ref()}

      # As in `Backpex.Integration.Options.AdapterTest`: only the adapter calls of this test's LiveViews are forwarded.
      :telemetry.attach(
        handler_id,
        RecordingAdapter.event(),
        fn _event, _measurements, metadata, _config ->
          if test_pid in [metadata.pid | metadata.callers], do: send(test_pid, {:adapter_call, metadata.function})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)
    end

    test "of an item on the page of the index view reads the item and shows its new values", %{conn: conn} do
      note = insert(:note, title: "Old title")
      {:ok, view, _html} = live(conn, ~p"/admin/recording-notes")
      flush_adapter_calls()

      note = note |> Ecto.Changeset.change(title: "New title") |> Repo.update!()
      send(view.pid, {"backpex:updated", note})

      assert render(view) =~ "New title"
      assert_received {:adapter_call, :read}
    end

    test "of an item on another page of the index view counts the items without reading the item", %{conn: conn} do
      # A page holds 15 notes. The titles have the same length, so none is part of another.
      notes = for number <- 10..25, do: insert(:note, title: "Paged note #{number}")
      {:ok, view, html} = live(conn, ~p"/admin/recording-notes")
      [off_page_note] = Enum.reject(notes, &(html =~ &1.title))
      flush_adapter_calls()

      off_page_note = off_page_note |> Ecto.Changeset.change(title: "New title") |> Repo.update!()
      send(view.pid, {"backpex:updated", off_page_note})

      refute render(view) =~ "New title"
      assert_received {:adapter_call, :count}
      refute_received {:adapter_call, :read}
    end

    test "of the shown item reads it again and shows its new values", %{conn: conn} do
      note = insert(:note, title: "Old title")
      {:ok, view, _html} = live(conn, ~p"/admin/recording-notes/#{note.id}/show")
      flush_adapter_calls()

      note = note |> Ecto.Changeset.change(title: "New title") |> Repo.update!()
      send(view.pid, {"backpex:updated", note})

      assert render(view) =~ "New title"
      assert_received {:adapter_call, :read}
    end

    test "of another item makes no adapter call in the show view", %{conn: conn} do
      note = insert(:note, title: "Shown title")
      other_note = insert(:note)
      {:ok, view, _html} = live(conn, ~p"/admin/recording-notes/#{note.id}/show")
      flush_adapter_calls()

      # Changed without an event of its own, so the new title only shows up if the view reads its item again.
      note |> Ecto.Changeset.change(title: "Changed unannounced") |> Repo.update!()
      send(view.pid, {"backpex:updated", other_note})

      html = render(view)
      assert html =~ "Shown title"
      refute html =~ "Changed unannounced"
      refute_received {:adapter_call, _function}
    end
  end

  defp flush_adapter_calls do
    receive do
      {:adapter_call, _function} -> flush_adapter_calls()
    after
      0 -> :ok
    end
  end
end
