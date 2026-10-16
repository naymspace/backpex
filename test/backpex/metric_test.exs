defmodule Backpex.MetricTest do
  use ExUnit.Case, async: true

  describe "use BackpexWeb, :metric" do
    test "refuses to compile a metric that still defines query/3 without data/3" do
      code = """
      defmodule Backpex.MetricTest.QueryMetric do
        use BackpexWeb, :metric

        def render(assigns), do: assigns
        def format(data, _format), do: data
        def query(query, _select, _repo), do: query
      end
      """

      assert_raise CompileError, ~r/defines query\/3, but metrics no longer query their data/, fn ->
        Code.compile_string(code)
      end
    end

    test "compiles a metric that defines data/3" do
      code = """
      defmodule Backpex.MetricTest.DataMetric do
        use BackpexWeb, :metric

        def render(assigns), do: assigns
        def format(data, _format), do: data
        def data(_metric, _criteria, _assigns), do: 1
      end
      """

      assert [{Backpex.MetricTest.DataMetric, _binary}] = Code.compile_string(code)
    end
  end
end
