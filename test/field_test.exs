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
end
