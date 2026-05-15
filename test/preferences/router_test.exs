defmodule Backpex.Preferences.RouterTest do
  use ExUnit.Case, async: false

  alias Backpex.Preferences.Adapters.Session
  alias Backpex.Preferences.Router

  doctest Router

  describe "routes/0 with no configured adapters" do
    setup do
      prior = Application.get_env(:backpex, Backpex.Preferences)
      on_exit(fn -> restore_env(prior) end)
      Application.delete_env(:backpex, Backpex.Preferences)
      :ok
    end

    test "falls back to a single :default Session route" do
      assert Router.routes() == [{:default, Session, []}]
    end
  end

  describe "resolve/2" do
    test "selects the most specific wildcard pattern" do
      routes = [
        {"global.*", SessionA, []},
        {"resource.*", AdapterB, []},
        {:default, FallbackAdapter, []}
      ]

      assert {SessionA, []} = Router.resolve("global.theme", routes)
      assert {AdapterB, []} = Router.resolve("resource:MyApp.MyLive:columns", routes)
    end

    test "picks the exact pattern over a wildcard regardless of config order" do
      routes = [
        {"global.*", Wildcard, []},
        {"global.theme", Specific, foo: :bar}
      ]

      assert {Specific, [foo: :bar]} = Router.resolve("global.theme", routes)
    end

    test "falls back to :default when no key-specific pattern matches" do
      routes = [
        {"global.*", GlobalAdapter, []},
        {:default, DefaultAdapter, []}
      ]

      assert {DefaultAdapter, []} = Router.resolve("custom.whatever", routes)
    end

    test "raises ArgumentError when nothing (not even :default) matches" do
      routes = [{"global.*", Adapter, []}]

      assert_raise ArgumentError, ~r/no Backpex.Preferences adapter matches key/, fn ->
        Router.resolve("resource.foo", routes)
      end
    end

    test "raises ArgumentError with a clear message when no routes are configured" do
      assert_raise ArgumentError, ~r/no Backpex.Preferences adapters configured/, fn ->
        Router.resolve("global.theme", [])
      end
    end

    test "accepts two-tuple routes (module without opts)" do
      routes = [{:default, Session}]
      assert {Session, []} = Router.resolve("anything", Router.default_routes() ++ routes)
    end

    test "deterministic tie-break between two equal-depth wildcards" do
      # When two wildcards sit at the same depth (e.g. "resource.*" and
      # "global.*"), only one can match any given key — the pattern whose
      # first segment equals the key's first segment. Document the behavior:
      # "global.theme" matches "global.*", not "resource.*", regardless of
      # the order they appear in config.
      routes = [
        {"resource.*", A, []},
        {"global.*", B, []}
      ]

      assert {B, []} = Router.resolve("global.theme", routes)
      assert {A, []} = Router.resolve("resource.anything", routes)

      # Reverse the order — result is the same.
      routes_reversed = [
        {"global.*", B, []},
        {"resource.*", A, []}
      ]

      assert {B, []} = Router.resolve("global.theme", routes_reversed)
      assert {A, []} = Router.resolve("resource.anything", routes_reversed)
    end

    test "non-wildcard exact match beats a wildcard at a different depth" do
      # A shorter exact pattern at the same segment count as a wildcard still
      # beats the wildcard because exact patterns have higher specificity.
      routes = [
        {"global.theme", SpecificA, []},
        {"global.*", BroadB, []}
      ]

      assert {SpecificA, []} = Router.resolve("global.theme", routes)
      assert {BroadB, []} = Router.resolve("global.sidebar_open", routes)
    end
  end

  describe "resolve/2 with match-function patterns" do
    test "match function routes a key to its adapter" do
      routes = [
        {&String.ends_with?(&1, ":columns"), ColumnsAdapter, []},
        {:default, FallbackAdapter, []}
      ]

      assert {ColumnsAdapter, []} = Router.resolve("resource:MyApp.MyLive:columns", routes)
      # A key that does not satisfy the function falls through to :default.
      assert {FallbackAdapter, []} = Router.resolve("resource:MyApp.MyLive:order", routes)
    end

    test "match function beats a more-specific string pattern" do
      # Documents the "functions are the most specific tier" rule. Even an
      # exact string pattern for the key loses to a match function that also
      # matches.
      routes = [
        {"resource:MyApp.MyLive:columns", StringAdapter, []},
        {&String.ends_with?(&1, ":columns"), FunAdapter, []}
      ]

      assert {FunAdapter, []} = Router.resolve("resource:MyApp.MyLive:columns", routes)
    end

    test "match function beats :default even when :default appears first and the function appears last" do
      routes = [
        {:default, FallbackAdapter, []},
        {"resource.*", WildcardAdapter, []},
        {&String.ends_with?(&1, ":columns"), FunAdapter, []}
      ]

      assert {FunAdapter, []} = Router.resolve("resource:MyApp.MyLive:columns", routes)
    end

    test "first match function in config order wins when multiple functions match" do
      # Both functions return true for this key. First-in-config-order wins
      # (the max_by tie-break inherits Enum.filter's preserved list order).
      routes = [
        {fn _key -> true end, FirstFunAdapter, []},
        {fn _key -> true end, SecondFunAdapter, []}
      ]

      assert {FirstFunAdapter, []} = Router.resolve("anything", routes)

      # Swap the order — result swaps too, confirming order is load-bearing.
      reversed = [
        {fn _key -> true end, SecondFunAdapter, []},
        {fn _key -> true end, FirstFunAdapter, []}
      ]

      assert {SecondFunAdapter, []} = Router.resolve("anything", reversed)
    end

    test "match function does not interfere with the existing wildcard-conflict check" do
      # Two conflicting wildcards would normally raise. Inserting a function
      # route between them must not rescue or alter that check.
      routes_without_fun = [
        {"resource.foo.*", AdapterA, []},
        {"resource.*", AdapterB, []}
      ]

      routes_with_fun = [
        {"resource.foo.*", AdapterA, []},
        {&String.ends_with?(&1, ":columns"), FunAdapter, []},
        {"resource.*", AdapterB, []}
      ]

      assert_raise ArgumentError, ~r/conflicting Backpex.Preferences routes/, fn ->
        Router.normalize(routes_without_fun)
      end

      assert_raise ArgumentError, ~r/conflicting Backpex.Preferences routes/, fn ->
        Router.normalize(routes_with_fun)
      end

      # A function between two non-conflicting wildcards still normalizes cleanly.
      clean_routes = [
        {"resource.foo.*", AdapterA, []},
        {&String.ends_with?(&1, ":columns"), FunAdapter, []},
        {"resource.foo.bar.*", AdapterB, []}
      ]

      assert [_first, _second, _third] = Router.normalize(clean_routes)
    end
  end

  describe "normalize/1 input validation" do
    test "raises ArgumentError with a friendly message for a non-module adapter" do
      assert_raise ArgumentError,
                   ~r/expected adapter module for route .+ got: :not_a_module/,
                   fn ->
                     Router.normalize([{"foo.*", :not_a_module, []}])
                   end
    end

    test "raises ArgumentError for a three-tuple with non-keyword opts" do
      assert_raise ArgumentError, ~r/invalid Backpex.Preferences route entry/, fn ->
        Router.normalize([{"foo.*", SomeAdapter, "not a keyword list"}])
      end
    end

    test "raises ArgumentError when the adapter is nil" do
      # A nil module is a common copy-paste mistake; the validation message
      # must call it out by name so the config author can find the offending
      # entry without spelunking through stack traces.
      assert_raise ArgumentError, ~r/got: nil/, fn ->
        Router.normalize([{"foo.*", nil, []}])
      end
    end

    test "raises ArgumentError for a non-string, non-:default pattern" do
      assert_raise ArgumentError, ~r/invalid Backpex.Preferences route pattern/, fn ->
        Router.normalize([{123, SomeAdapter, []}])
      end
    end

    test "raises ArgumentError for an empty-string pattern" do
      assert_raise ArgumentError, ~r/must not be an empty string/, fn ->
        Router.normalize([{"", SomeAdapter, []}])
      end
    end

    test "raises ArgumentError for a bare atom (not a tuple)" do
      assert_raise ArgumentError, ~r/invalid Backpex.Preferences route entry/, fn ->
        Router.normalize([:default])
      end
    end

    test "raises ArgumentError naming both patterns when a later broader route swallows an earlier narrower one" do
      routes = [
        {"resource.foo.*", AdapterA, []},
        {"resource.*", AdapterB, []}
      ]

      assert_raise ArgumentError, ~r/conflicting Backpex.Preferences routes/, fn ->
        Router.normalize(routes)
      end
    end

    test "does not raise when a later narrower route sits inside an earlier broader one" do
      routes = [
        {"resource.foo.*", AdapterA, []},
        {"resource.foo.bar.*", AdapterB, []}
      ]

      assert [_first, _second] = Router.normalize(routes)
    end

    test "does not raise when nested patterns route to the same adapter" do
      routes = [
        {"resource.foo.*", SameAdapter, []},
        {"resource.*", SameAdapter, []}
      ]

      assert [_first, _second] = Router.normalize(routes)
    end

    test "rejects a 0-arity function pattern with a clear arity message" do
      assert_raise ArgumentError,
                   ~r/match function must be arity 1.+got arity 0/s,
                   fn ->
                     Router.normalize([{fn -> true end, SomeAdapter, []}])
                   end
    end

    test "rejects a 2-arity function pattern with a clear arity message" do
      assert_raise ArgumentError,
                   ~r/match function must be arity 1.+got arity 2/s,
                   fn ->
                     Router.normalize([{fn _a, _b -> true end, SomeAdapter, []}])
                   end
    end

    test "accepts a 1-arity function pattern" do
      assert [{pattern, SomeAdapter, []}] =
               Router.normalize([{&String.ends_with?(&1, ":columns"), SomeAdapter, []}])

      assert is_function(pattern, 1)
    end
  end

  describe "resolve_prefix/2" do
    test "picks the wildcard that owns the subtree when the query is the wildcard's prefix" do
      # Query "resource.foo" must go to FakeEctoAdapter, not fall through to
      # Session — a wildcard rooted at the query's own prefix owns the subtree.
      routes = [
        {"resource.foo.*", FakeEctoAdapter, []},
        {:default, Session, []}
      ]

      assert {FakeEctoAdapter, []} = Router.resolve_prefix("resource.foo", routes)
    end

    test "picks a wildcard whose prefix is an ancestor of the query (owns the whole subtree)" do
      routes = [
        {"resource.*", EctoAdapter, []},
        {:default, Session, []}
      ]

      assert {EctoAdapter, []} = Router.resolve_prefix("resource.foo", routes)
      assert {EctoAdapter, []} = Router.resolve_prefix("resource.foo.bar", routes)
    end

    test "picks a wildcard whose prefix is a descendant of the query (lives inside the subtree)" do
      # Query is "resource"; the only matching wildcard points at "resource.foo.*".
      # The route is inside the query's subtree, so it still owns the relevant slice.
      routes = [
        {"resource.foo.*", EctoAdapter, []},
        {:default, Session, []}
      ]

      assert {EctoAdapter, []} = Router.resolve_prefix("resource", routes)
    end

    test "falls through to :default when no wildcard/exact route is on the query's lineage" do
      routes = [
        {"resource.*", EctoAdapter, []},
        {:default, Session, []}
      ]

      assert {Session, []} = Router.resolve_prefix("global.theme", routes)
    end

    test "exact pattern equal to the query wins over an ancestor wildcard" do
      routes = [
        {"global.theme", SpecificA, []},
        {"global.*", BroadB, []}
      ]

      assert {SpecificA, []} = Router.resolve_prefix("global.theme", routes)
    end

    test "wildcard rooted at the query wins over an ancestor-rooted wildcard" do
      # Broader pattern first, narrower second — the narrower route carves out
      # a subtree of the broader one and is allowed to do so.
      routes = [
        {"resource.*", BroadB, []},
        {"resource.foo.*", SpecificA, []}
      ]

      # Query is "resource.foo" — SpecificA's prefix equals the query; it
      # beats the broader "resource.*" (ancestor-rooted wildcard).
      assert {SpecificA, []} = Router.resolve_prefix("resource.foo", routes)
    end

    test "regression: exact get_map for a key covered only by :default returns from Session" do
      routes = [
        {"resource.*", EctoAdapter, []},
        {:default, Session, []}
      ]

      assert {Session, []} = Router.resolve_prefix("global.theme", routes)
    end

    test "raises ArgumentError with a clear message when no routes are configured" do
      assert_raise ArgumentError, ~r/no Backpex.Preferences adapters configured/, fn ->
        Router.resolve_prefix("global.theme", [])
      end
    end

    test "raises ArgumentError when nothing matches and there is no :default" do
      routes = [{"global.*", Adapter, []}]

      assert_raise ArgumentError, ~r/no Backpex.Preferences adapter matches prefix/, fn ->
        Router.resolve_prefix("resource.foo", routes)
      end
    end

    test "ignores match-function routes even when they would match individual keys" do
      # The function would match every key in the "resource" subtree if it
      # were considered, but subtree owner lookups deliberately exclude
      # match-function routes. The :default adapter must win for the subtree.
      routes = [
        {fn _key -> true end, FunAdapter, []},
        {:default, SessionAdapter, []}
      ]

      assert {SessionAdapter, []} = Router.resolve_prefix("resource.foo", routes)
    end

    test "ignores match-function routes so string patterns still own their subtree" do
      # Even when a function precedes a matching string wildcard, the string
      # wildcard owns the subtree because functions are excluded from
      # resolve_prefix entirely.
      routes = [
        {fn _key -> true end, FunAdapter, []},
        {"resource.*", EctoAdapter, []},
        {:default, SessionAdapter, []}
      ]

      assert {EctoAdapter, []} = Router.resolve_prefix("resource.foo", routes)
    end

    test "raises when only a match-function route is configured and no :default exists" do
      routes = [{fn _key -> true end, FunAdapter, []}]

      assert_raise ArgumentError, ~r/no Backpex.Preferences adapter matches prefix/, fn ->
        Router.resolve_prefix("anything", routes)
      end
    end
  end

  defp restore_env(nil), do: Application.delete_env(:backpex, Backpex.Preferences)
  defp restore_env(value), do: Application.put_env(:backpex, Backpex.Preferences, value)
end
