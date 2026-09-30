defmodule Backpex.FieldTest do
  use ExUnit.Case, async: true

  alias Backpex.Field
  alias Backpex.Fields.Text
  alias Backpex.FieldTest.PubSub
  alias Backpex.LiveResource
  alias Phoenix.LiveView.Socket

  # Simulates a LiveResource fields/0 callback structure
  defmodule UpstreamPrices do
    def fields do
      [
        name: %{module: Text, label: "Name"},
        upstream_price: %{module: Backpex.Fields.Number, label: "Upstream Price", readonly: true},
        override_price: %{module: Backpex.Fields.Number, label: "Our Price"}
      ]
    end
  end

  describe "drop_readonly_changes/3" do
    test "readonly fields are correctly filtered from LiveResource fields" do
      fields = UpstreamPrices.fields()
      change = %{"name" => "Backpack", "upstream_price" => "100", "override_price" => "200"}

      filtered = Field.drop_readonly_changes(change, fields, %{})

      assert filtered == %{"name" => "Backpack", "override_price" => "200"}
      refute Map.has_key?(filtered, "upstream_price")
    end

    test "readonly function field is filtered when condition is true" do
      fields = [
        name: %{module: Text, label: "Name"},
        secret: %{module: Text, label: "Secret", readonly: fn assigns -> assigns[:role] == :viewer end}
      ]

      change = %{"name" => "Test", "secret" => "hidden"}

      # As viewer - secret should be filtered
      filtered = Field.drop_readonly_changes(change, fields, %{role: :viewer})
      assert filtered == %{"name" => "Test"}

      # As admin - secret should remain
      filtered = Field.drop_readonly_changes(change, fields, %{role: :admin})
      assert filtered == %{"name" => "Test", "secret" => "hidden"}
    end
  end

  describe "readonly?/2" do
    test "returns true for boolean true" do
      assert Field.readonly?(%{readonly: true}, %{}) == true
    end

    test "returns false for boolean false" do
      assert Field.readonly?(%{readonly: false}, %{}) == false
    end

    test "returns false when readonly key is missing" do
      assert Field.readonly?(%{}, %{}) == false
    end

    test "evaluates function against assigns" do
      readonly_fn = fn assigns -> assigns[:role] == :viewer end

      assert Field.readonly?(%{readonly: readonly_fn}, %{role: :viewer}) == true
      assert Field.readonly?(%{readonly: readonly_fn}, %{role: :admin}) == false
    end
  end

  defmodule InlineEditLive do
    @moduledoc false
    def config(:adapter), do: Backpex.Test.StubAdapter
    def pubsub, do: [server: PubSub, topic: "field_test"]

    def can?(assigns, action, _item) do
      send(self(), {:can?, action, assigns})
      true
    end

    def on_item_updated(socket, item) do
      send(self(), {:on_item_updated, socket, item})
      socket
    end
  end

  describe "handle_index_editable/3" do
    setup do
      start_supervised!({Phoenix.PubSub, name: PubSub})
      :ok
    end

    test "saves the change with the rendered assigns of the LiveView and the item of the field" do
      item = %{id: 1, title: "Before"}
      socket = field_socket(item)

      LiveResource.put_rendered_assigns(%{
        __changed__: %{},
        live_resource: InlineEditLive,
        item: nil,
        current_user: :user
      })

      assert {:noreply, socket} = Field.handle_index_editable(socket, "After", %{title: "After"})

      assert_received {:can?, :edit, %{current_user: :user, item: ^item}}
      assert_received {:adapter, :update, ^item, %{title: "After"}}
      assert_received {:on_item_updated, %Socket{assigns: %{name: :title}}, ^item}
      assert socket.assigns.valid
      assert socket.assigns.form.params == %{"value" => "After"}
    end

    test "saves the change with the assigns of the field outside of a LiveView of the LiveResource" do
      item = %{id: 1, title: "Before"}
      socket = field_socket(item)

      LiveResource.put_rendered_assigns(%{live_resource: UpstreamPrices, current_user: :user})

      assert {:noreply, socket} = Field.handle_index_editable(socket, "After", %{title: "After"})

      assert_received {:can?, :edit, %{name: :title, item: ^item} = assigns}
      refute Map.has_key?(assigns, :current_user)
      assert_received {:adapter, :update, ^item, %{title: "After"}}
      assert socket.assigns.valid
    end
  end

  defp field_socket(item) do
    %Socket{assigns: %{__changed__: %{}, name: :title, item: item, fields: [], live_resource: InlineEditLive}}
  end
end
