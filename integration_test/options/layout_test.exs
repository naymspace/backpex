defmodule Backpex.Integration.Options.LayoutTest do
  @moduledoc """
  Checks the deprecated `layout` option: a LiveResource that sets it instead of defining the `c:Backpex.LiveResource.layout/1`
  callback renders its views inside that layout.

  The option warns when a LiveResource is compiled, and the support files of the test app are compiled with
  `--warnings-as-errors`. So these LiveResources are compiled here, where the warning is captured, and the layout is
  resolved with `Backpex.HTML.Layout`, which renders every view of a LiveResource, instead of through a route.
  """
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO
  import Phoenix.Component, only: [sigil_H: 2]

  alias Backpex.HTML.Layout

  defmodule Layouts do
    @moduledoc false
    use Phoenix.Component

    def tuple_layout(assigns) do
      ~H"""
      <main id="tuple-layout">{render_slot(@inner_block)}</main>
      """
    end

    def fun_layout(assigns) do
      ~H"""
      <main id="fun-layout">{render_slot(@inner_block)}</main>
      """
    end
  end

  @live_resources ~S'''
  defmodule Backpex.Integration.Options.LayoutTest.TupleLayoutNoteLive do
    use Backpex.LiveResource,
      adapter_config: [
        schema: Backpex.Test.Note,
        repo: Backpex.Test.Repo,
        update_changeset: &Backpex.Test.Note.changeset/3,
        create_changeset: &Backpex.Test.Note.changeset/3
      ],
      layout: {Backpex.Integration.Options.LayoutTest.Layouts, :tuple_layout}

    def singular_name, do: "Note"
    def plural_name, do: "Notes"
  end

  defmodule Backpex.Integration.Options.LayoutTest.FunLayoutNoteLive do
    use Backpex.LiveResource,
      adapter_config: [
        schema: Backpex.Test.Note,
        repo: Backpex.Test.Repo,
        update_changeset: &Backpex.Test.Note.changeset/3,
        create_changeset: &Backpex.Test.Note.changeset/3
      ],
      layout: &Backpex.Integration.Options.LayoutTest.Layouts.fun_layout/1

    def singular_name, do: "Note"
    def plural_name, do: "Notes"
  end

  defmodule Backpex.Integration.Options.LayoutTest.NoLayoutNoteLive do
    use Backpex.LiveResource,
      adapter_config: [
        schema: Backpex.Test.Note,
        repo: Backpex.Test.Repo,
        update_changeset: &Backpex.Test.Note.changeset/3,
        create_changeset: &Backpex.Test.Note.changeset/3
      ]

    def singular_name, do: "Note"
    def plural_name, do: "Notes"
  end
  '''

  setup_all do
    {_modules, warnings} = with_io(:stderr, fn -> Code.compile_string(@live_resources, __ENV__.file) end)

    %{warnings: warnings}
  end

  test "warns that the option is deprecated when the LiveResource is compiled", %{warnings: warnings} do
    assert warnings =~
             ":layout option is deprecated. Use the layout/1 callback instead to avoid compile-time dependencies."
  end

  test "renders the views inside the layout of a {module, function} tuple" do
    live_resource = Backpex.Integration.Options.LayoutTest.TupleLayoutNoteLive

    assert live_resource.layout(%{}) == {Layouts, :tuple_layout}
    assert render_in_layout(live_resource) =~ ~s(<main id="tuple-layout"><p>View content</p></main>)
  end

  test "renders the views inside the layout of a function" do
    live_resource = Backpex.Integration.Options.LayoutTest.FunLayoutNoteLive

    assert render_in_layout(live_resource) =~ ~s(<main id="fun-layout"><p>View content</p></main>)
  end

  test "raises without the option and the layout/1 callback" do
    assert_raise ArgumentError, ~r/No layout configured for .*NoLayoutNoteLive/, fn ->
      render_in_layout(Backpex.Integration.Options.LayoutTest.NoLayoutNoteLive)
    end
  end

  defp render_in_layout(live_resource) do
    %{__changed__: nil, live_resource: live_resource}
    |> Layout.layout_with_content(fn assigns -> ~H"<p>View content</p>" end)
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
  end
end
