defmodule Backpex.AdapterTest do
  use ExUnit.Case, async: true

  describe "use Backpex.Adapter" do
    test "returns the field config schema given to use" do
      defmodule OptionAdapter do
        @moduledoc false
        use Backpex.Adapter, field_config_schema: [tenant: [type: :atom]], supports: :all
      end

      assert OptionAdapter.field_config_schema() == [tenant: [type: :atom]]
    end

    test "lets the adapter define its own field config schema" do
      defmodule CallbackAdapter do
        @moduledoc false
        use Backpex.Adapter, supports: :all

        @impl Backpex.Adapter
        def field_config_schema, do: [tenant: [type: :atom]]
      end

      assert CallbackAdapter.field_config_schema() == [tenant: [type: :atom]]
    end

    test "raises without the :supports option, so that no adapter claims to run a query by default" do
      assert_raise ArgumentError, ~r/has to pass the :supports option.*`supports: :all`.*`supports: \[\]`/s, fn ->
        defmodule NoSupportsAdapter do
          @moduledoc false
          use Backpex.Adapter
        end
      end
    end

    test "raises for a :supports option that is neither :all nor a list" do
      assert_raise ArgumentError, ~r/to be :all or a list of features, got: :none/, fn ->
        defmodule InvalidSupportsAdapter do
          @moduledoc false
          use Backpex.Adapter, supports: :none
        end
      end
    end

    test "defines supports?/2 from the :supports option" do
      defmodule SortAdapter do
        @moduledoc false
        use Backpex.Adapter, supports: [{:filter, :==}, :sort]
      end

      assert SortAdapter.supports?(SomeLive, :sort)
      assert SortAdapter.supports?(SomeLive, :filter)
      assert SortAdapter.supports?(SomeLive, {:filter, :==})
      refute SortAdapter.supports?(SomeLive, {:filter, :in})
      refute SortAdapter.supports?(SomeLive, :limit)
    end
  end
end
