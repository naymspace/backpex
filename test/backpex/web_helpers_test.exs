defmodule Backpex.WebHelpersTest do
  use ExUnit.Case, async: false

  @fixture Path.expand("../fixtures/web_helpers/extension_modules.fixture", __DIR__)

  @fixture_modules [
    Backpex.WebHelpersTest.Helpers,
    Backpex.WebHelpersTest.Web,
    Backpex.WebHelpersTest.ItemActionBackpexFirst,
    Backpex.WebHelpersTest.ItemActionWebFirst,
    Backpex.WebHelpersTest.FilterBackpexFirst,
    Backpex.WebHelpersTest.FilterWebFirst,
    Backpex.WebHelpersTest.SelectFilterBackpexFirst,
    Backpex.WebHelpersTest.SelectFilterWebFirst,
    Backpex.WebHelpersTest.MetricBackpexFirst,
    Backpex.WebHelpersTest.MetricWebFirst,
    Backpex.WebHelpersTest.Field
  ]

  test "Backpex extensions compile with host web helpers without warnings" do
    purge_fixture_modules()
    on_exit(&purge_fixture_modules/0)

    assert {:ok, modules, %{compile_warnings: [], runtime_warnings: []}} =
             Kernel.ParallelCompiler.compile([@fixture],
               max_concurrency: 1,
               return_diagnostics: true
             )

    assert Enum.sort(modules) == Enum.sort(@fixture_modules)
  end

  defp purge_fixture_modules do
    Enum.each(@fixture_modules, fn module ->
      :code.purge(module)
      :code.delete(module)
    end)
  end
end
