defmodule Backpex.FieldTest do
  use ExUnit.Case, async: true

  alias Backpex.Field
  alias Backpex.Fields.Text
  alias Backpex.FieldTest.PubSub
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

  defmodule Author do
    @moduledoc false
    use Ecto.Schema

    schema("authors", do: nil)
  end

  defmodule Article do
    @moduledoc false
    use Ecto.Schema

    schema("articles", do: belongs_to(:author, Author))
  end

  defmodule ArticleLive do
    @moduledoc false
    def adapter_config(:schema), do: Article
  end

  describe "index_editable_change/3" do
    test "saves the value to the field of the same name by default" do
      assert Text.index_editable_change({:title, %{}}, "After", %{}) == %{title: "After"}
    end

    test "saves the value of a belongs to field to its foreign key" do
      assert Backpex.Fields.BelongsTo.index_editable_change({:author, %{}}, "1", %{live_resource: ArticleLive}) ==
               %{author_id: "1"}
    end
  end

  describe "assign_index_form/1" do
    test "assigns the value of the item as a valid form" do
      assigns = Field.assign_index_form(%{__changed__: %{}, value: "Title"})

      assert assigns.form.params == %{"value" => "Title"}
      assert assigns.valid
    end

    test "assigns the value of an edit the index view could not save as an invalid form" do
      assigns = Field.assign_index_form(%{__changed__: %{}, value: "Title", index_edit: %{value: "", valid: false}})

      assert assigns.form.params == %{"value" => ""}
      refute assigns.valid
    end
  end

  describe "handle_index_editable/3" do
    setup do
      start_supervised!({Phoenix.PubSub, name: PubSub})
      :ok
    end

    test "saves the change with the assigns of the field component" do
      item = %{id: 1, title: "Before"}
      socket = field_socket(item)

      assert {:noreply, socket} = Field.handle_index_editable(socket, "After", %{title: "After"})

      assert_received {:can?, :edit, %{name: :title, item: ^item}}
      assert_received {:adapter, :update, ^item, %{title: "After"}}
      assert_received {:on_item_updated, %Socket{assigns: %{name: :title}}, ^item}
      assert socket.assigns.valid
      assert socket.assigns.form.params == %{"value" => "After"}
    end
  end

  defp field_socket(item) do
    %Socket{assigns: %{__changed__: %{}, name: :title, item: item, fields: [], live_resource: InlineEditLive}}
  end
end
