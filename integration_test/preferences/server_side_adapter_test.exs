defmodule Backpex.Integration.Preferences.ServerSideAdapterTest do
  @moduledoc """
  The Session adapter cannot write outside an HTTP request cycle and says so (`{:error, :requires_http}`), so its writes
  round-trip through the browser. Route the resource keys at an adapter that CAN write in place and the round-trip must
  disappear entirely: the LiveResource asks its adapter how the write lands instead of assuming the browser has to carry
  it. Nothing else about the interaction changes.
  """
  # The tests change the application env of `Backpex.Preferences`.
  use Backpex.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Backpex.Preferences.Adapters.Session
  alias Backpex.Preferences.Keys, as: PrefKeys
  alias Backpex.Preferences.LiveView, as: PrefLiveView
  alias Backpex.Test.InMemoryPreferencesAdapter

  @resource_mod Backpex.Test.PostLive

  @event_name PrefLiveView.event_name()

  setup do
    InMemoryPreferencesAdapter.reset()
    prior = Application.get_env(:backpex, Backpex.Preferences)

    Application.put_env(:backpex, Backpex.Preferences,
      adapters: [
        {"resource.*", InMemoryPreferencesAdapter, []},
        {:default, Session, []}
      ]
    )

    on_exit(fn ->
      case prior do
        nil -> Application.delete_env(:backpex, Backpex.Preferences)
        value -> Application.put_env(:backpex, Backpex.Preferences, value)
      end
    end)

    :ok
  end

  test "column toggle persists through the adapter and queues no push_event", %{conn: conn} do
    insert(:post, title: "Alpha", published: true)

    conn
    |> visit(~p"/admin/posts?filters[published][]=published")
    |> uncheck("Title")
    |> refute_preference_push_event()

    assert %{"title" => false} = Map.fetch!(InMemoryPreferencesAdapter.dump(), PrefKeys.columns(@resource_mod))
  end

  test "sort change persists through the adapter and queues no push_event", %{conn: conn} do
    insert(:post, title: "Alpha", published: true)

    conn
    |> visit(~p"/admin/posts?filters[published][]=published")
    |> click_link("Title")
    |> refute_preference_push_event()

    assert %{"by" => "title", "direction" => "asc"} =
             Map.fetch!(InMemoryPreferencesAdapter.dump(), PrefKeys.order(@resource_mod))
  end

  # Not one preference event over the whole mount + click cycle — the `%{}` pattern matches any payload, so this refutes
  # them all.
  defp refute_preference_push_event(session) do
    unwrap(session, fn view ->
      refute_push_event(view, @event_name, %{})
      render(view)
    end)
  end
end
