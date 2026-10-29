defmodule Backpex.ItemActions.DeleteTest do
  use ExUnit.Case, async: true

  alias Backpex.ItemActions.Delete
  alias Backpex.Test.StubAdapter
  alias Phoenix.LiveView.Socket

  # Refuses to delete an item with `locked: true` and reports every hook call.
  defmodule LockingLive do
    @moduledoc false
    def config(:adapter), do: StubAdapter
    def config(:primary_key), do: :id
    def pubsub, do: [server: Backpex.ItemActions.DeleteTest.PubSub, topic: "delete_test"]

    def translate({msg, opts}),
      do: Enum.reduce(opts, msg, fn {key, value}, acc -> String.replace(acc, "%{#{key}}", to_string(value)) end)

    def singular_name, do: "Item"
    def plural_name, do: "Items"

    def on_item_deleting(_socket, item) do
      send(self(), {:on_item_deleting, item})

      case item do
        %{locked: true, id: id} -> {:error, "Item #{id} is locked."}
        %{invalid_return: true} -> :error
        _item -> :ok
      end
    end

    def on_item_deleted(socket, item) do
      send(self(), {:on_item_deleted, item})
      socket
    end
  end

  setup do
    start_supervised!({Phoenix.PubSub, name: __MODULE__.PubSub})
    :ok
  end

  describe "handle/3" do
    test "deletes the items when on_item_deleting/2 allows each of them" do
      items = [%{id: 1}, %{id: 2}]

      assert {:ok, socket} = Delete.handle(socket(), items, %{})

      assert_received {:on_item_deleting, %{id: 1}}
      assert_received {:on_item_deleting, %{id: 2}}
      assert_received {:adapter, :delete_all, ^items}
      assert_received {:on_item_deleted, %{id: 1}}
      assert_received {:on_item_deleted, %{id: 2}}
      assert socket.assigns.flash == %{"info" => "2 Items have been deleted successfully."}
    end

    test "deletes none of the items and shows the message when on_item_deleting/2 refuses one" do
      items = [%{id: 1}, %{id: 2, locked: true}, %{id: 3}]

      assert {:ok, socket} = Delete.handle(socket(), items, %{})

      assert_received {:on_item_deleting, %{id: 1}}
      assert_received {:on_item_deleting, %{id: 2}}
      refute_received {:on_item_deleting, %{id: 3}}
      refute_received {:adapter, :delete_all, _items}
      refute_received {:on_item_deleted, _item}
      assert socket.assigns.flash == %{"error" => "Item 2 is locked."}
    end

    test "raises when on_item_deleting/2 returns something else" do
      assert_raise ArgumentError, ~r/on_item_deleting\/2/, fn ->
        Delete.handle(socket(), [%{id: 1, invalid_return: true}], %{})
      end

      refute_received {:adapter, :delete_all, _items}
    end
  end

  defp socket do
    Phoenix.Component.assign(%Socket{}, :live_resource, LockingLive)
  end
end
