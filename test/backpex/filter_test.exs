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

        assert_raise CompileError, ~r/defines query\/4, but filters no longer build queries/, fn ->
          Code.compile_string(code)
        end
      end
    end
  end
end
