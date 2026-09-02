defmodule Backpex.ItemActionTest do
  use ExUnit.Case, async: true

  alias Backpex.ItemAction
  alias Backpex.Test.LiveResources.AllowAll
  alias Backpex.Test.LiveResources.NoAdmins
  alias Phoenix.LiveView.Socket

  defmodule EchoAction do
    @moduledoc false
    def handle(socket, items, _data) do
      send(self(), {:handled, items, Map.get(socket.assigns, :item_action_key)})
      send(self(), {:handled_selection, Map.get(socket.assigns, :selected_items)})

      {:ok, socket}
    end
  end

  defmodule BadReturnAction do
    @moduledoc false
    def handle(_socket, _items, _data), do: :oops
  end

  # `stub_records` is the fake data layer `Backpex.Test.StubAdapter.get/4` reads. Tests hand the
  # gate a store that differs from the selection to simulate another actor changing (or deleting) a
  # row while it sat in `selected_items`.
  defp build_socket(live_resource, records \\ []) do
    %Socket{}
    |> Phoenix.Component.assign(:live_resource, live_resource)
    |> Phoenix.Component.assign(:live_action, :index)
    |> Phoenix.Component.assign(:stub_records, Map.new(records, &{&1.id, &1}))
  end

  defp after_handle(socket), do: {:after_handle, socket}

  describe "authorize_fresh!/3" do
    test "returns the records as they are now, in the order they were given" do
      fresh = [%{id: 1, role: :user, name: "renamed"}, %{id: 2, role: :user}]
      socket = build_socket(AllowAll, fresh)

      stale = [%{id: 1, role: :user, name: "old"}, %{id: 2, role: :user}]

      assert ItemAction.authorize_fresh!(socket, :user_soft_delete, stale) == fresh
    end

    test "authorizes the reloaded record, not the selected snapshot" do
      # The row was `role: :user` when it was selected and is `role: :admin` now. `NoAdmins` denies
      # the current one, and that is the answer that has to win.
      socket = build_socket(NoAdmins, [%{id: 1, role: :admin}])

      assert_raise Backpex.ForbiddenError, fn ->
        ItemAction.authorize_fresh!(socket, :user_soft_delete, [%{id: 1, role: :user}])
      end
    end

    test "lets a record that became authorized through" do
      # The mirror image: denied when it was rendered, allowed now.
      socket = build_socket(NoAdmins, [%{id: 1, role: :user}])

      assert ItemAction.authorize_fresh!(socket, :user_soft_delete, [%{id: 1, role: :admin}]) == [%{id: 1, role: :user}]
    end

    test "raises NoResultsError when a selected row has vanished" do
      socket = build_socket(AllowAll, [%{id: 2, role: :user}])

      assert_raise Backpex.NoResultsError, fn ->
        ItemAction.authorize_fresh!(socket, :user_soft_delete, [%{id: 1, role: :user}, %{id: 2, role: :user}])
      end
    end

    test "reads nothing for an empty selection" do
      socket = build_socket(AllowAll)

      assert ItemAction.authorize_fresh!(socket, :user_soft_delete, []) == []

      refute_received {:adapter, :get, _primary_value}
    end
  end

  describe "handle_item_action/5" do
    test "passes the full list to handle/3 and assigns item_action_key" do
      items = [%{id: 1, role: :user}, %{id: 2, role: :user}]
      socket = build_socket(AllowAll, items)

      assert {:after_handle, _socket} =
               ItemAction.handle_item_action(socket, %{module: EchoAction}, :user_soft_delete, items, &after_handle/1)

      assert_received {:handled, ^items, :user_soft_delete}
    end

    test "dispatches the reloaded records rather than the selected snapshot" do
      fresh = [%{id: 1, role: :user, name: "renamed"}]
      stale = [%{id: 1, role: :user, name: "old"}]
      socket = build_socket(AllowAll, fresh)

      assert {:after_handle, _socket} =
               ItemAction.handle_item_action(socket, %{module: EchoAction}, :user_soft_delete, stale, &after_handle/1)

      assert_received {:handled, ^fresh, :user_soft_delete}
    end

    test "puts the reloaded records into selected_items so handle/3 sees one selection" do
      fresh = [%{id: 1, role: :user, name: "renamed"}]
      socket = build_socket(AllowAll, fresh)

      assert {:after_handle, _socket} =
               ItemAction.handle_item_action(
                 socket,
                 %{module: EchoAction},
                 :user_soft_delete,
                 [%{id: 1, role: :user, name: "old"}],
                 &after_handle/1
               )

      assert_received {:handled_selection, ^fresh}
    end

    test "clears item_action_key once the dispatch is over" do
      socket = build_socket(AllowAll, [%{id: 1}])

      # The key belongs to one dispatch. Leaving it set would let a later dispatch, or anything
      # rendered afterwards, read the key of an action that already finished.
      assert {:after_handle, socket} =
               ItemAction.handle_item_action(
                 socket,
                 %{module: EchoAction},
                 :user_soft_delete,
                 [%{id: 1}],
                 &after_handle/1
               )

      assert socket.assigns.item_action_key == nil
    end

    test "raises ForbiddenError when a single item is unauthorized and never calls handle/3" do
      items = [%{id: 1, role: :user}, %{id: 2, role: :admin}]
      socket = build_socket(NoAdmins, items)

      assert_raise Backpex.ForbiddenError, fn ->
        ItemAction.handle_item_action(socket, %{module: EchoAction}, :delete, items, &after_handle/1)
      end

      refute_received {:handled, _items, _key}
    end

    test "raises ForbiddenError when a selected item became unauthorized after it was selected" do
      # Nothing about the selection says so — only the reload does.
      socket = build_socket(NoAdmins, [%{id: 1, role: :admin}])

      assert_raise Backpex.ForbiddenError, fn ->
        ItemAction.handle_item_action(socket, %{module: EchoAction}, :delete, [%{id: 1, role: :user}], &after_handle/1)
      end

      refute_received {:handled, _items, _key}
    end

    test "raises NoResultsError for a nil item and never calls handle/3" do
      socket = build_socket(AllowAll)

      assert_raise Backpex.NoResultsError, fn ->
        ItemAction.handle_item_action(socket, %{module: EchoAction}, :delete, [nil], &after_handle/1)
      end

      refute_received {:handled, _items, _key}
    end

    test "raises NoResultsError when a selected row vanished and never calls handle/3" do
      socket = build_socket(AllowAll)

      assert_raise Backpex.NoResultsError, fn ->
        ItemAction.handle_item_action(socket, %{module: EchoAction}, :delete, [%{id: 1, role: :user}], &after_handle/1)
      end

      refute_received {:handled, _items, _key}
    end

    test "never calls handle/3 for an empty selection but still runs after_handle" do
      socket = build_socket(AllowAll)

      assert {:after_handle, _socket} =
               ItemAction.handle_item_action(socket, %{module: EchoAction}, :delete, [], &after_handle/1)

      refute_received {:handled, _items, _key}
    end

    test "raises ArgumentError on an unexpected return value" do
      socket = build_socket(AllowAll, [%{id: 1}])

      assert_raise ArgumentError, ~r/Invalid return value/, fn ->
        ItemAction.handle_item_action(socket, %{module: BadReturnAction}, :delete, [%{id: 1}], &after_handle/1)
      end
    end
  end
end
