defmodule Backpex.FieldTest do
  use ExUnit.Case, async: true

  alias Backpex.Field

  # Simulates a LiveResource fields/0 callback structure
  defmodule UpstreamPrices do
    def fields do
      [
        name: %{module: Backpex.Fields.Text, label: "Name"},
        upstream_price: %{module: Backpex.Fields.Number, label: "Upstream Price", readonly: true},
        override_price: %{module: Backpex.Fields.Number, label: "Our Price"}
      ]
    end
  end

  defmodule IndexOptionsField do
    use Backpex.Field

    @impl Backpex.Field
    def render_value(assigns), do: ~H""

    @impl Backpex.Field
    def render_form(assigns), do: ~H""

    @impl Backpex.Field
    def render_index_form(assigns), do: ~H""

    @impl Phoenix.LiveComponent
    def update(assigns, socket), do: {:ok, socket |> assign(assigns) |> assign(:updated, true)}

    @impl Backpex.Field
    def assign_index_forms(sockets) do
      send(self(), {:assign_index_forms, Enum.map(sockets, & &1.assigns.item.id)})

      Enum.map(sockets, &assign(&1, :options, [&1.assigns.item.id]))
    end
  end

  defmodule DroppingIndexOptionsField do
    use Backpex.Field

    @impl Backpex.Field
    def render_value(assigns), do: ~H""

    @impl Backpex.Field
    def render_form(assigns), do: ~H""

    @impl Backpex.Field
    def assign_index_forms(_sockets), do: []
  end

  defmodule PlainField do
    use Backpex.Field

    @impl Backpex.Field
    def render_value(assigns), do: ~H""

    @impl Backpex.Field
    def render_form(assigns), do: ~H""
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
        name: %{module: Backpex.Fields.Text, label: "Name"},
        secret: %{module: Backpex.Fields.Text, label: "Secret", readonly: fn assigns -> assigns[:role] == :viewer end}
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

  describe "update_many/2" do
    test "is used as update_many/1 by fields implementing assign_index_forms/1" do
      assert function_exported?(IndexOptionsField, :update_many, 1)
      refute function_exported?(PlainField, :update_many, 1)
    end

    test "updates all sockets and assigns the index forms in order" do
      sockets =
        IndexOptionsField.update_many([
          field_assigns(1, :index, true),
          field_assigns(2, :form, true),
          field_assigns(3, :index, false),
          field_assigns(4, :index, true)
        ])

      assert_received {:assign_index_forms, [1, 4]}
      assert Enum.map(sockets, & &1.assigns.item.id) == [1, 2, 3, 4]
      assert Enum.all?(sockets, & &1.assigns.updated)
      assert Enum.map(sockets, &Map.get(&1.assigns, :options)) == [[1], nil, nil, [4]]
    end

    test "merges the assigns into fields without update/2" do
      [socket] = DroppingIndexOptionsField.update_many([field_assigns(1, :form, true)])

      assert socket.assigns.item.id == 1
    end

    test "does not call assign_index_forms/1 without index forms" do
      IndexOptionsField.update_many([field_assigns(1, :form, true), field_assigns(2, :index, false)])

      refute_received {:assign_index_forms, _ids}
    end

    test "raises when assign_index_forms/1 does not return a socket per index form" do
      assert_raise ArgumentError, ~r/must return one socket per given socket/, fn ->
        DroppingIndexOptionsField.update_many([field_assigns(1, :index, true)])
      end
    end
  end

  defp field_assigns(id, type, index_editable) do
    assigns = %{item: %{id: id}, type: type, live_action: :index, field_options: %{index_editable: index_editable}}

    {assigns, %Phoenix.LiveView.Socket{}}
  end
end
