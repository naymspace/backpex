defmodule Backpex.LiveResource.IndexTest do
  use ExUnit.Case, async: true

  alias Backpex.LiveResource.Index
  alias Backpex.Test.StubAdapter
  alias Phoenix.LiveView.Socket

  defmodule FailingAdapter do
    @moduledoc false
    def change(item, attrs, _fields, _assigns, _live_resource, _opts), do: {:changeset, item, attrs}

    def update({:changeset, item, attrs}, _live_resource) do
      send(self(), {:adapter, :update, item, attrs})
      {:error, :invalid}
    end
  end

  defmodule InlineEditLive do
    @moduledoc false
    def config(:adapter), do: StubAdapter
    def config(:primary_key), do: :id
    def pubsub, do: [server: Backpex.LiveResource.IndexTest.PubSub, topic: "index_test"]

    def can?(assigns, action, _item) do
      send(self(), {:can?, action, assigns})
      true
    end

    def on_item_updated(socket, item) do
      send(self(), {:on_item_updated, socket, item})
      socket
    end
  end

  defmodule FailingInlineEditLive do
    @moduledoc false
    def config(:adapter), do: Backpex.LiveResource.IndexTest.FailingAdapter
    def config(:primary_key), do: :id
    def can?(_assigns, _action, _item), do: true
  end

  @fields [
    title: %{module: Backpex.Fields.Text, label: "Title", index_editable: true},
    body: %{module: Backpex.Fields.Text, label: "Body"}
  ]

  setup do
    start_supervised!({Phoenix.PubSub, name: __MODULE__.PubSub})
    :ok
  end

  describe "handle_event/3 with an inline edit" do
    test "saves the change with all assigns of the LiveView and the item and shows the saved item" do
      item = %{id: 1, title: "Before"}
      saved_item = %{id: 1, title: "After"}
      socket = socket(InlineEditLive, item, %{stub_records: %{1 => saved_item}})

      assert {:noreply, socket} = Index.handle_event("index-edit", params("title", "1", "After"), socket)

      assert_received {:can?, :edit, %{current_user: :user, item: ^item}}
      assert_received {:adapter, :update, ^item, %{title: "After"}}
      assert_received {:on_item_updated, %Socket{}, ^item}
      assert socket.assigns.items == [saved_item]
      assert socket.assigns.index_edits == %{}
    end

    test "keeps the value of an edit that is not saved as invalid until the item is saved" do
      item = %{id: 1, title: "Before"}
      socket = socket(FailingInlineEditLive, item)

      assert {:noreply, socket} = Index.handle_event("index-edit", params("title", "1", ""), socket)

      assert socket.assigns.items == [item]
      assert socket.assigns.index_edits == %{{:title, 1} => %{value: "", valid: false}}
    end

    test "saves nothing for a field that is not index editable or an item that is not on the page" do
      socket = socket(InlineEditLive, %{id: 1, title: "Before"})

      assert {:noreply, ^socket} = Index.handle_event("index-edit", params("body", "1", "After"), socket)
      assert {:noreply, ^socket} = Index.handle_event("index-edit", params("title", "2", "After"), socket)
      assert {:noreply, ^socket} = Index.handle_event("index-edit", params("unknown", "1", "After"), socket)

      refute_received {:adapter, :update, _item, _change}
    end
  end

  defp params(field, item_id, value),
    do: %{"index_edit" => %{"field" => field, "item" => item_id}, "index_form" => %{"value" => value}}

  defp socket(live_resource, item, assigns \\ %{}) do
    %Socket{
      assigns:
        Map.merge(
          %{
            __changed__: %{},
            live_resource: live_resource,
            live_action: :index,
            fields: @fields,
            items: [item],
            selected_items: [],
            index_edits: %{},
            current_user: :user
          },
          assigns
        )
    }
  end
end
