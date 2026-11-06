defmodule Backpex.WebHelpersTest.Entrypoints do
  @moduledoc false

  def html do
    quote do
      use Phoenix.Component
    end
  end

  def live_component do
    quote do
      use Phoenix.LiveComponent
    end
  end

  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end

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
    Backpex.WebHelpersTest.Field,
    Backpex.WebHelpersTest.FieldAttributeOptions,
    Backpex.WebHelpersTest.BaseField,
    Backpex.WebHelpersTest.WrappedField
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

  describe "Backpex.Field compile errors" do
    test "raises when :live_component is not given literally" do
      assert_raise ArgumentError, ~r/expected :live_component to be given literally/, fn ->
        compile_field("""
        @options [live_component: {Backpex.WebHelpersTest.Entrypoints, :live_component}]

        use Backpex.Field, @options
        """)
      end
    end

    test "raises when the :live_component entrypoint does not set up a LiveComponent" do
      assert_raise ArgumentError, ~r/to be a Phoenix.LiveComponent/, fn ->
        compile_field("""
        use Backpex.Field, live_component: {Backpex.WebHelpersTest.Entrypoints, :html}
        """)
      end
    end

    test "raises when Phoenix.Component is set up in addition to the field" do
      assert_raise ArgumentError, ~r/to set up Phoenix.Component only once/, fn ->
        compile_field("""
        use Backpex.Field, live_component: {Backpex.WebHelpersTest.Entrypoints, :live_component}
        use Backpex.WebHelpersTest.Entrypoints, :html
        """)
      end
    end
  end

  defp compile_field(setup) do
    module = Backpex.WebHelpersTest.InvalidField

    on_exit(fn ->
      :code.purge(module)
      :code.delete(module)
    end)

    Code.compile_string("""
    defmodule #{inspect(module)} do
      #{setup}

      def render_value(assigns), do: ~H"<span>value</span>"
      def render_form(assigns), do: ~H"<span>form</span>"
    end
    """)
  end

  defp purge_fixture_modules do
    Enum.each(@fixture_modules, fn module ->
      :code.purge(module)
      :code.delete(module)
    end)
  end
end
