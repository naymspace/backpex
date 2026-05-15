defmodule Backpex.Preferences.KeyTest do
  # `async: false` because `validate/1` reads application env for
  # `:extra_prefixes`, and one describe block mutates that env.
  use ExUnit.Case, async: false

  alias Backpex.Preferences.Key

  doctest Key

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

    test "colon wins over dots when an Elixir.-prefixed module appears" do
      assert Key.parse("Elixir.Foo.Bar:suffix") == ["Elixir.Foo.Bar", "suffix"]
    end

    test "trailing colon produces an empty final segment" do
      assert Key.parse("resource:Foo:") == ["resource", "Foo", ""]
    end

    test "leading colon produces an empty first segment" do
      assert Key.parse(":foo") == ["", "foo"]
    end

    test "a stray colon flips the entire key to colon-split (no mixed mode)" do
      assert Key.parse("resource.MyApp:columns") == ["resource.MyApp", "columns"]
    end

    test "empty string returns a single empty segment (does not raise)" do
      assert Key.parse("") == [""]
    end

    test "tolerates non-ASCII characters inside module segments" do
      assert Key.parse("Elixir.Módulo:columns") == ["Elixir.Módulo", "columns"]
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

  describe "known_prefixes/0" do
    test "returns the built-in prefixes by default" do
      assert Key.known_prefixes() == ["global", "resource", "custom"]
    end

    test "appends app-supplied extra prefixes from config, deduplicated" do
      prior = Application.get_env(:backpex, Key)

      Application.put_env(:backpex, Key, extra_prefixes: ["experimental", "global"])

      try do
        # "global" is deduplicated because it is already built-in. "experimental"
        # is appended after the built-ins.
        assert Key.known_prefixes() == ["global", "resource", "custom", "experimental"]
      after
        restore_env(prior)
      end
    end

    test "ignores non-binary entries in extra_prefixes" do
      prior = Application.get_env(:backpex, Key)

      Application.put_env(:backpex, Key, extra_prefixes: [:atom_prefix, "experimental", nil])

      try do
        assert Key.known_prefixes() == ["global", "resource", "custom", "experimental"]
      after
        restore_env(prior)
      end
    end
  end

  describe "validate/1" do
    test "returns :ok for known built-in prefixes" do
      assert Key.validate("global.theme") == :ok
      assert Key.validate("resource:MyApp.UserLive:columns") == :ok
      assert Key.validate("custom.dashboard.view_mode") == :ok
    end

    test "returns {:error, :unknown_prefix} for typos" do
      assert Key.validate("globl.theme") == {:error, :unknown_prefix}
      assert Key.validate("resources.foo") == {:error, :unknown_prefix}
      assert Key.validate("other.foo") == {:error, :unknown_prefix}
    end

    test "returns {:error, :empty} for empty string" do
      assert Key.validate("") == {:error, :empty}
    end

    test "returns {:error, :malformed} for keys with an empty first segment" do
      # `":foo"` parses to `["", "foo"]` — first segment is empty.
      assert Key.validate(":foo") == {:error, :malformed}
      # `".foo"` parses to `["", "foo"]` via dot-split — same shape.
      assert Key.validate(".foo") == {:error, :malformed}
    end

    test "accepts app-registered extra prefixes" do
      prior = Application.get_env(:backpex, Key)

      Application.put_env(:backpex, Key, extra_prefixes: ["experimental"])

      try do
        assert Key.validate("experimental.foo") == :ok
      after
        restore_env(prior)
      end
    end
  end

  defp restore_env(nil), do: Application.delete_env(:backpex, Key)
  defp restore_env(value), do: Application.put_env(:backpex, Key, value)
end
