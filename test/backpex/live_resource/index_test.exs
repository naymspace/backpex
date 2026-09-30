defmodule Backpex.LiveResource.IndexTest do
  use ExUnit.Case, async: true

  alias Backpex.LiveResource.Index
  alias Backpex.Test.StubAdapter
  alias Phoenix.LiveComponent.CID
  alias Phoenix.LiveView.Socket

  defmodule InlineEditLive do
    @moduledoc false
    def config(:adapter), do: StubAdapter
    def pubsub, do: [server: Backpex.LiveResource.IndexTest.PubSub, topic: "index_test"]

    def can?(assigns, action, _item) do
      send(self(), {:can?, action, assigns})
      Map.get(assigns, :can?, true)
    end

    def on_item_updated(socket, item) do
      send(self(), {:on_item_updated, socket, item})
      socket
    end
  end

  setup do
    start_supervised!({Phoenix.PubSub, name: __MODULE__.PubSub})
    :ok
  end

  describe "handle_info/2 with an inline edit" do
    test "saves the change with all assigns of the LiveView and reports the result to the field component" do
      component = %CID{cid: 1}
      item = %{id: 1, title: "Before"}
      socket = socket(%{current_user: :user})

      assert {:noreply, ^socket} =
               Index.handle_info(
                 {:backpex_index_editable, %{component: component, item: item, change: %{title: "After"}}},
                 socket
               )

      assert_received {:can?, :edit, %{current_user: :user, item: ^item}}
      assert_received {:adapter, :change, _opts}
      assert_received {:adapter, :update, ^item, %{title: "After"}}
      assert_received {:on_item_updated, ^socket, ^item}
      assert_received {:phoenix, :send_update, {^component, %{valid: true, backpex_index_editable: true}}}
    end

    test "raises and saves nothing when the item may not be edited" do
      socket = socket(%{can?: false})

      assert_raise Backpex.ForbiddenError, fn ->
        Index.handle_info(
          {:backpex_index_editable, %{component: %CID{cid: 1}, item: %{id: 1}, change: %{title: "After"}}},
          socket
        )
      end

      refute_received {:adapter, :update, _item, _change}
      refute_received {:phoenix, :send_update, _update}
    end
  end

  defp socket(assigns) do
    %Socket{assigns: Map.merge(%{__changed__: %{}, fields: [], live_resource: InlineEditLive}, assigns)}
  end
end
