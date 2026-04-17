defmodule Backpex.Preferences.KeyTest do
  use ExUnit.Case, async: true

  alias Backpex.Preferences.Key

  doctest Backpex.Preferences.Key

  describe "parse/1" do
    test "splits dot-separated keys" do
      assert Key.parse("global.theme") == ["global", "theme"]
      assert Key.parse("a.b.c.d") == ["a", "b", "c", "d"]
    end

    test "splits colon-separated keys without colliding on embedded dots" do
      assert Key.parse("resource:MyApp.UserLive:columns") == ["resource", "MyApp.UserLive", "columns"]
      assert Key.parse("custom:Foo.Bar.Baz:suffix") == ["custom", "Foo.Bar.Baz", "suffix"]
    end

    test "treats single-segment keys as one path element" do
      assert Key.parse("global") == ["global"]
    end
  end

  describe "encode_module/1" do
    test "returns the inspect form of an Elixir module" do
      assert Key.encode_module(Backpex.Preferences) == "Backpex.Preferences"
    end
  end

  describe "resource_key/2" do
    test "builds a colon-separated key so module dots do not collide" do
      assert Key.resource_key(Backpex.Preferences, "columns") == "resource:Backpex.Preferences:columns"
    end

    test "round-trips through parse/1 into three segments" do
      key = Key.resource_key(Backpex.Preferences, "metrics_visible")
      assert Key.parse(key) == ["resource", "Backpex.Preferences", "metrics_visible"]
    end
  end

  describe "match?/2" do
    test "trailing wildcard matches any first-segment-equal key" do
      assert Key.match?("global.*", "global.theme")
      assert Key.match?("global.*", "global.sidebar_open")
      refute Key.match?("global.*", "resource.foo")
    end

    test "wildcard works across key encodings (dot and colon forms)" do
      assert Key.match?("resource.*", "resource.MyLive.columns")
      assert Key.match?("resource.*", "resource:MyApp.MyLive:columns")
    end

    test "exact patterns match only by equality" do
      assert Key.match?("global.theme", "global.theme")
      refute Key.match?("global.theme", "global.theme.nested")
    end
  end
end
