defmodule Backpex.HTML.ResourceTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias Backpex.HTML.Resource

  describe "filter_forms/1" do
    test "renders a form with a stable id so LiveView can perform form recovery" do
      html =
        render_component(&Resource.filter_forms/1,
          filters: [],
          filter_options: %{},
          live_resource: nil
        )

      assert html =~ ~s(id="filter-form")
      assert html =~ ~s(phx-change="change-filter")
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
