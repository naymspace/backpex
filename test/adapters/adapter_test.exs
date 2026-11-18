defmodule Backpex.AdapterTest do
  use ExUnit.Case, async: true

  describe "use Backpex.Adapter" do
    test "returns the field config schema given to use" do
      defmodule OptionAdapter do
        @moduledoc false
        use Backpex.Adapter, field_config_schema: [tenant: [type: :atom]]
      end

      assert OptionAdapter.field_config_schema() == [tenant: [type: :atom]]
    end

    test "lets the adapter define its own field config schema" do
      defmodule CallbackAdapter do
        @moduledoc false
        use Backpex.Adapter

        @impl Backpex.Adapter
        def field_config_schema, do: [tenant: [type: :atom]]
      end

      assert CallbackAdapter.field_config_schema() == [tenant: [type: :atom]]
    end
  end
end
