defmodule Backpex.HTML.ResourceTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias Backpex.HTML.Resource

  defmodule ContextLive do
    @moduledoc false
    def translate({msg, _opts}), do: msg
    def config(:full_text_search), do: nil
  end

  defmodule MarkerFilter do
    @moduledoc false
    use Phoenix.Component

    def label, do: "Marker"

    def render_form(assigns) do
      ~H"""
      <span id="marker">{@marker}</span>
      """
    end
  end

  describe "resource_filters/1" do
    test "passes the given context to the callbacks of filters" do
      html =
        render_component(&Resource.resource_filters/1,
          live_resource: ContextLive,
          search_placeholder: "Search",
          filters: [marker: %{module: MarkerFilter}],
          marker: "assigns",
          backpex_context: %{marker: "context"}
        )

      assert html =~ ~s(<span id="marker">context</span>)
    end

    test "passes its own assigns to the callbacks of filters when called without a context" do
      html =
        render_component(&Resource.resource_filters/1,
          live_resource: ContextLive,
          search_placeholder: "Search",
          filters: [marker: %{module: MarkerFilter}],
          marker: "assigns",
          backpex_view_context: %{marker: "view context"}
        )

      assert html =~ ~s(<span id="marker">assigns</span>)
    end
  end

  describe "lv_reserved_assigns/0" do
    test "includes every assign reserved by Phoenix.LiveView" do
      reserved = Resource.lv_reserved_assigns()

      for key <- [:flash, :uploads, :streams, :socket, :myself] do
        assert key in reserved, "expected #{inspect(key)} in lv_reserved_assigns/0"
      end
    end

    test "dropping the reserved set removes :streams from a parent-style assigns map" do
      assigns = %{streams: %{example: :ref}, foo: 1, bar: 2}

      result = Map.drop(assigns, Resource.lv_reserved_assigns())

      refute Map.has_key?(result, :streams)
      assert result == %{foo: 1, bar: 2}
    end
  end
end
