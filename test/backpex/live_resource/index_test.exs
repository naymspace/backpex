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

  defmodule LegacyField do
    @moduledoc false
    def render_index_form(_assigns), do: nil
  end

  @fields [
    title: %{module: Backpex.Fields.Text, label: "Title", index_editable: true},
    body: %{module: Backpex.Fields.Text, label: "Body"},
    legacy: %{module: LegacyField, label: "Legacy", index_editable: true},
    flag: %{module: Backpex.Fields.Boolean, label: "Flag", index_editable: &__MODULE__.flaggable/1},
    code: %{module: Backpex.Fields.Text, label: "Code", index_editable: true, readonly: true},
    note: %{module: Backpex.Fields.Text, label: "Note", index_editable: true, readonly: &__MODULE__.locked/1}
  ]

  def flaggable(%{item: item}), do: if(Map.get(item, :flaggable), do: :yes)

  def locked(%{item: item}), do: Map.get(item, :locked)

  setup do
    start_supervised!({Phoenix.PubSub, name: __MODULE__.PubSub})
    :ok
  end

  describe "handle_event/3 with an inline edit" do
    test "saves the change with all assigns of the LiveView and the item and shows the saved item" do
      item = %{id: 1, title: "Before"}
      saved_item = %{id: 1, title: "After"}
      other_edit = {{:title, 2}, %{value: "", valid: false}}

      socket =
        socket(InlineEditLive, item, %{
          stub_records: %{1 => saved_item},
          index_edits: Map.new([{{:title, 1}, %{value: "", valid: false}}, other_edit])
        })

      assert {:noreply, socket} = Index.handle_event("index-edit", params("title", "1", "After"), socket)

      assert_received {:can?, :edit, %{current_user: :user, name: :title, item: ^item}}
      assert_received {:adapter, :update, ^item, %{title: "After"}}
      assert_received {:on_item_updated, %Socket{}, ^item}
      assert socket.assigns.items == [saved_item]
      assert socket.assigns.index_edits == Map.new([other_edit])
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

    test "saves nothing for a field that does not implement index_editable_change/3" do
      socket = socket(InlineEditLive, %{id: 1, legacy: "Before"})

      assert {:noreply, ^socket} = Index.handle_event("index-edit", params("legacy", "1", "After"), socket)

      refute_received {:adapter, :update, _item, _change}
    end

    test "saves nil for a form without a value" do
      item = %{id: 1, title: "Before"}
      socket = socket(InlineEditLive, item, %{stub_records: %{1 => %{item | title: nil}}})
      params = "title" |> params("1", nil) |> Map.delete("index_form")

      assert {:noreply, _socket} = Index.handle_event("index-edit", params, socket)
      assert_received {:adapter, :update, ^item, %{title: nil}}
    end

    test "ignores an inline edit without a field or an item" do
      socket = socket(InlineEditLive, %{id: 1, title: "Before"})

      assert {:noreply, ^socket} = Index.handle_event("index-edit", %{"index_form" => %{"value" => "After"}}, socket)
      assert {:noreply, ^socket} = Index.handle_event("index-edit", %{"index_edit" => %{"field" => "title"}}, socket)

      refute_received {:adapter, :update, _item, _change}
    end

    test "saves nothing for a readonly field" do
      socket = socket(InlineEditLive, %{id: 1, title: "Before", locked: true})

      assert {:noreply, ^socket} = Index.handle_event("index-edit", params("code", "1", "After"), socket)
      assert {:noreply, ^socket} = Index.handle_event("index-edit", params("note", "1", "After"), socket)

      refute_received {:adapter, :update, _item, _change}
    end

    test "saves a field whose readonly function returns nil" do
      item = %{id: 1, note: "Before"}
      socket = socket(InlineEditLive, item, %{stub_records: %{1 => %{id: 1, note: "After"}}})

      assert {:noreply, _socket} = Index.handle_event("index-edit", params("note", "1", "After"), socket)

      assert_received {:adapter, :update, ^item, %{note: "After"}}
    end

    test "saves a field whose index_editable function returns a truthy value" do
      item = %{id: 1, flag: false, flaggable: true}
      socket = socket(InlineEditLive, item, %{stub_records: %{1 => %{item | flag: true}}})

      assert {:noreply, _socket} = Index.handle_event("index-edit", params("flag", "1", "true"), socket)
      assert_received {:adapter, :update, ^item, %{flag: "true"}}

      socket = socket(InlineEditLive, %{item | flaggable: false})

      assert {:noreply, ^socket} = Index.handle_event("index-edit", params("flag", "1", "true"), socket)
      refute_received {:adapter, :update, _item, _change}
    end
  end

  defmodule VisibleFilter do
    @moduledoc false
    def can?(assigns), do: Map.get(assigns, :show_filter, false)
  end

  defmodule FilterLive do
    @moduledoc false
    def filters(_assigns), do: [published: %{module: VisibleFilter}]
  end

  describe "assign_active_filters/1" do
    test "evaluates the filters with the assigns of the render" do
      assigns = %{__changed__: %{}, live_resource: FilterLive, filters: [], show_filter: true}

      assert %{filters: [published: %{module: VisibleFilter}], __changed__: changed} =
               Index.assign_active_filters(assigns)

      assert Map.has_key?(changed, :filters)
    end

    test "keeps the filters unchanged when they are the same" do
      filters = [published: %{module: VisibleFilter}]
      assigns = %{__changed__: %{}, live_resource: FilterLive, filters: filters, show_filter: true}

      assert %{filters: ^filters, __changed__: changed} = Index.assign_active_filters(assigns)
      refute Map.has_key?(changed, :filters)
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
