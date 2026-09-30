defmodule Backpex.FieldTest do
  use ExUnit.Case, async: true

  alias Backpex.Field
  alias Backpex.Fields.Text
  alias Phoenix.LiveComponent.CID
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

  defmodule StrictUpdateField do
    @moduledoc false
    use Backpex.Field

    @impl Phoenix.LiveComponent
    def update(%{name: name} = assigns, socket), do: {:ok, socket |> assign(assigns) |> assign(:updated, name)}

    @impl Backpex.Field
    def render_value(assigns), do: ~H""

    @impl Backpex.Field
    def render_form(assigns), do: ~H""
  end

  describe "update/2 of a field" do
    test "assigns the result of an inline edit without calling the update/2 of the field" do
      socket = %Socket{assigns: %{__changed__: %{}, valid: true}}

      assert {:ok, socket} = StrictUpdateField.update(%{backpex_index_editable: %{valid: false}}, socket)
      assert socket.assigns.valid == false
      refute Map.has_key?(socket.assigns, :updated)

      assert {:ok, socket} = Text.update(%{backpex_index_editable: %{valid: false}}, socket)
      assert socket.assigns.valid == false
    end

    test "passes all other assigns to the update/2 of the field or assigns them" do
      socket = %Socket{assigns: %{__changed__: %{}}}

      assert {:ok, socket} = StrictUpdateField.update(%{name: :title}, socket)
      assert socket.assigns.updated == :title

      assert {:ok, socket} = Text.update(%{name: :title}, socket)
      assert socket.assigns.name == :title
    end
  end

  describe "handle_index_editable/3" do
    test "keeps the value in the form and leaves saving the change to the index LiveView" do
      component = %CID{cid: 1}
      item = %{id: 1, title: "Before"}
      socket = %Socket{assigns: %{__changed__: %{}, myself: component, item: item}}

      assert {:noreply, socket} = Field.handle_index_editable(socket, "After", %{title: "After"})

      assert socket.assigns.form.params == %{"value" => "After"}
      assert_received {:backpex_index_editable, %{component: ^component, item: ^item, change: %{title: "After"}}}
    end
  end
end
