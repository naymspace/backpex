defmodule Backpex.Preferences.KeysTest do
  use ExUnit.Case, async: true

  alias Backpex.Preferences.Key
  alias Backpex.Preferences.Keys

  doctest Backpex.Preferences.Keys

  describe "global keys" do
    test "theme/0 returns the canonical theme key" do
      assert Keys.theme() == "global.theme"
    end

    test "sidebar_open/0 returns the canonical sidebar-open key" do
      assert Keys.sidebar_open() == "global.sidebar_open"
    end

    test "sidebar_section_prefix/0 returns the canonical prefix for sidebar section map reads" do
      assert Keys.sidebar_section_prefix() == "global.sidebar_section"
    end
  end

  describe "per-resource keys" do
    test "columns/1 builds a colon-separated key with the module segment" do
      assert Keys.columns(MyApp.UserLive) == "resource:MyApp.UserLive:columns"
    end

    test "order/1 builds a colon-separated key with the module segment" do
      assert Keys.order(MyApp.UserLive) == "resource:MyApp.UserLive:order"
    end

    test "filters/1 builds a colon-separated key with the module segment" do
      assert Keys.filters(MyApp.UserLive) == "resource:MyApp.UserLive:filters"
    end

    test "metrics_visible/1 builds a colon-separated key with the module segment" do
      assert Keys.metrics_visible(MyApp.UserLive) == "resource:MyApp.UserLive:metrics_visible"
    end

    test "per-resource keys round-trip through Backpex.Preferences.Key.parse/1" do
      # Guards against a per-resource helper ever drifting away from the
      # encoding used everywhere else.
      segments =
        MyApp.UserLive
        |> Keys.columns()
        |> Key.parse()

      assert segments == ["resource", "MyApp.UserLive", "columns"]
    end
  end
end
