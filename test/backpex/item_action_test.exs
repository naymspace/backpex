defmodule Backpex.ItemActionTest do
  use ExUnit.Case, async: true

  alias Backpex.ItemAction
  alias Phoenix.LiveView.Socket

  defmodule AllowAll do
    @moduledoc false
    def can?(_assigns, _action, _item), do: true
  end

  defmodule NoAdmins do
    @moduledoc false
    def can?(_assigns, _action, %{role: :admin} = _item), do: false
    def can?(_assigns, _action, _item), do: true
  end

  defmodule EchoAction do
    @moduledoc false
    def handle(socket, items, _data) do
      send(self(), {:handled, items, Map.get(socket.assigns, :item_action_key)})

      {:ok, socket}
    end
  end

  defmodule BadReturnAction do
    @moduledoc false
    def handle(_socket, _items, _data), do: :oops
  end

  defp build_socket(live_resource) do
    Phoenix.Component.assign(%Socket{}, :live_resource, live_resource)
  end

  defp after_handle(socket), do: {:after_handle, socket}

  describe "handle_item_action/5" do
    test "passes the full list to handle/3 and assigns item_action_key" do
      items = [%{id: 1, role: :user}, %{id: 2, role: :user}]

      assert {:after_handle, _socket} =
               ItemAction.handle_item_action(
                 build_socket(AllowAll),
                 %{module: EchoAction},
                 :user_soft_delete,
                 items,
                 &after_handle/1
               )

      assert_received {:handled, ^items, :user_soft_delete}
    end

    test "raises ForbiddenError when a single item is unauthorized and never calls handle/3" do
      items = [%{id: 1, role: :user}, %{id: 2, role: :admin}]

      assert_raise Backpex.ForbiddenError, fn ->
        ItemAction.handle_item_action(build_socket(NoAdmins), %{module: EchoAction}, :delete, items, &after_handle/1)
      end

      refute_received {:handled, _items, _key}
    end

    test "raises NoResultsError for a nil item and never calls handle/3" do
      assert_raise Backpex.NoResultsError, fn ->
        ItemAction.handle_item_action(build_socket(AllowAll), %{module: EchoAction}, :delete, [nil], &after_handle/1)
      end

      refute_received {:handled, _items, _key}
    end

    test "never calls handle/3 for an empty selection but still runs after_handle" do
      assert {:after_handle, _socket} =
               ItemAction.handle_item_action(
                 build_socket(AllowAll),
                 %{module: EchoAction},
                 :delete,
                 [],
                 &after_handle/1
               )

      refute_received {:handled, _items, _key}
    end

    test "raises ArgumentError on an unexpected return value" do
      assert_raise ArgumentError, ~r/Invalid return value/, fn ->
        ItemAction.handle_item_action(
          build_socket(AllowAll),
          %{module: BadReturnAction},
          :delete,
          [%{id: 1}],
          &after_handle/1
        )
      end
    end
  end
end
