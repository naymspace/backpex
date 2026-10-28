defmodule Backpex.Integration.Options.PubSubTest do
  @moduledoc """
  Checks the `pubsub` option: `Backpex.Test.PubSubNoteLive` broadcasts its events on the configured server and topic,
  and its index view reloads on events of that topic only.
  """
  use Backpex.ConnCase, async: true

  import Phoenix.LiveViewTest, only: [live: 2, render: 1]

  alias Backpex.Test.Note
  alias Backpex.Test.PubSubNoteLive

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
end
