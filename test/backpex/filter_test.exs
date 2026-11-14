defmodule Backpex.FilterTest do
  use ExUnit.Case, async: true

  describe "use Backpex.Filter" do
    test "refuses to compile a filter that still defines query/4, also on top of a built-in filter" do
      for {name, using} <- [QueryFilter: Backpex.Filter, QuerySelect: Backpex.Filters.Select] do
        code = """
        defmodule Backpex.FilterTest.#{name} do
          use #{inspect(using)}

          def query(query, _field, _value, _assigns), do: query
        end
        """

        assert_raise CompileError,
                     ~r/defines query\/4, but filters no longer build queries.*upgrading to v0\.25/s,
                     fn ->
                       Code.compile_string(code)
                     end
      end
    end

    test "the default condition/3 tells to implement it and names the upgrade guide" do
      defmodule WithoutCondition do
        @moduledoc false
        use Backpex.Filter
      end

      assert_raise RuntimeError, ~r/You must implement the condition\/3 callback.*upgrading to v0\.25/s, fn ->
        WithoutCondition.condition(:title, "a", %{})
      end
    end
  end
end
