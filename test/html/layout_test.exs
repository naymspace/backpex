defmodule Backpex.HTML.LayoutTest do
  use ExUnit.Case, async: true

  import Phoenix.Component

  alias Backpex.HTML.Layout

  defmodule TestLive do
    @moduledoc false
    use Phoenix.Component

    def layout(_assigns), do: {__MODULE__, :app}

    def app(assigns) do
      send(self(), {:layout_changed, assigns.__changed__})

      ~H"""
      <main>{render_slot(@inner_block)}</main>
      """
    end
  end

  describe "layout_with_content/2" do
    test "renders the content inside the layout and keeps the change tracking of the assigns" do
      assigns = %{__changed__: %{title: true}, live_resource: TestLive, title: "Title"}

      html =
        assigns
        |> Layout.layout_with_content(fn assigns -> ~H"<h1>{@title}</h1>" end)
        |> Phoenix.HTML.Safe.to_iodata()
        |> IO.iodata_to_binary()

      assert html =~ "<main><h1>Title</h1></main>"
      assert_received {:layout_changed, %{title: true, inner_block: true}}
    end
  end
end
