defmodule Backpex.Preferences.KeysTest do
  use ExUnit.Case, async: true

  alias Backpex.Preferences.Key
  alias Backpex.Preferences.Keys

  doctest Keys

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

  describe "valid_value?/2 accepts the shapes built-in readers expect" do
    test "each built-in leaf accepts its own shape" do
      assert Keys.valid_value?(Keys.theme(), "dark")
      assert Keys.valid_value?(Keys.sidebar_open(), false)
      assert Keys.valid_value?("global.sidebar_section.blog", false)
      columns = Keys.columns(MyApp.UserLive)
      metrics_visible = Keys.metrics_visible(MyApp.UserLive)
      order = Keys.order(MyApp.UserLive)
      filters = Keys.filters(MyApp.UserLive)

      assert Keys.valid_value?(columns, %{"name" => true})
      assert Keys.valid_value?(metrics_visible, true)
      assert Keys.valid_value?(order, %{"by" => "name"})
      assert Keys.valid_value?(filters, %{"status" => "active"})
    end

    test "keys Backpex owns no reader for still pass through" do
      assert Keys.valid_value?("custom.acme.anything", %{"a" => 1})
      assert Keys.valid_value?("global.unknown_future_key", %{"a" => 1})
      assert Keys.valid_value?("resource:MyApp.UserLive:unknown_suffix", %{"a" => 1})
    end
  end

  describe "valid_value?/2 rejects writes that would retype a built-in leaf" do
    # Adapters store at whatever depth they are handed, so a key naming an
    # interior node of a built-in path installs children no leaf check ever
    # saw. Reading one back then raises in the render — `to_string/1` on a map
    # for a section state, `data-theme` interpolation for the theme — 500ing
    # every Backpex page for the life of the store entry.
    test "an interior node of a built-in path is refused" do
      refute Keys.valid_value?("global", %{"theme" => %{}})
      refute Keys.valid_value?("global", "anything")
      refute Keys.valid_value?("global.sidebar_section", %{"blog" => %{}})
      refute Keys.valid_value?("resource", %{})
      refute Keys.valid_value?("resource:MyApp.UserLive", %{"columns" => "nonsense"})
    end

    test "a node below a built-in leaf is refused" do
      refute Keys.valid_value?("global.theme.x", "dark")
      refute Keys.valid_value?("global.sidebar_open.x", true)
      refute Keys.valid_value?("global.sidebar_section.blog.deep", true)
      refute Keys.valid_value?("resource:MyApp.UserLive:columns:x", true)
      refute Keys.valid_value?("resource:MyApp.UserLive:filters:x", %{})
    end

    test "rejection does not depend on the value being ill-shaped" do
      # The leaf shape is irrelevant: the *path* is what makes the write
      # unsafe, so even a boolean at `global.sidebar_section` is refused.
      refute Keys.valid_value?("global.sidebar_section", true)
      refute Keys.valid_value?("global.sidebar_section.blog.deep", false)
    end
  end
end
