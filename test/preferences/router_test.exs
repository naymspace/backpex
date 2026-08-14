defmodule Backpex.Preferences.RouterTest do
  use ExUnit.Case, async: false

  alias Backpex.Preferences.Adapters.Session
  alias Backpex.Preferences.Keys
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

    test "a nested wildcard carves a subtree out of a broader one, in either config order" do
      # Specificity alone decides, so the narrow route wins no matter where it
      # sits in the list. Both orders are legal config.
      narrow_first = [
        {"resource.foo.*", NarrowAdapter, []},
        {"resource.*", BroadAdapter, []}
      ]

      broad_first = Enum.reverse(narrow_first)

      for routes <- [narrow_first, broad_first] do
        assert {NarrowAdapter, []} = Router.resolve("resource.foo.columns", routes)
        assert {BroadAdapter, []} = Router.resolve("resource.other", routes)
      end
    end

    test "a wildcard also matches the bare key at its own prefix" do
      routes = [{"global.sidebar_section.*", SectionAdapter, []}, {:default, Fallback, []}]

      assert {SectionAdapter, []} = Router.resolve("global.sidebar_section.blog", routes)
      assert {SectionAdapter, []} = Router.resolve("global.sidebar_section", routes)
    end
  end

  describe "resolve/2 for per-resource keys" do
    # Regression: a per-resource route used to silently misroute. Patterns were
    # split on ".", keys on ":" (Key.parse/1), so "resource:MyApp.PostLive:*"
    # matched nothing and the key fell through to the next-broadest route
    # without a word. Patterns and keys now share one segmentation rule.
    setup do
      %{
        post_columns: Keys.columns(MyApp.PostLive),
        post_order: Keys.order(MyApp.PostLive),
        post_filters: Keys.filters(MyApp.PostLive),
        user_columns: Keys.columns(MyApp.UserLive)
      }
    end

    test "a per-resource wildcard owns exactly that resource's keys", ctx do
      routes = [
        {"resource:MyApp.PostLive:*", PostAdapter, []},
        {"resource.*", GenericAdapter, []},
        {:default, SessionAdapter, []}
      ]

      # The pattern is written against the key Backpex actually emits.
      assert ctx.post_columns == "resource:MyApp.PostLive:columns"

      assert {PostAdapter, []} = Router.resolve(ctx.post_columns, routes)
      assert {PostAdapter, []} = Router.resolve(ctx.post_order, routes)
      assert {PostAdapter, []} = Router.resolve(ctx.post_filters, routes)

      # Sibling resources are untouched by the carve-out.
      assert {GenericAdapter, []} = Router.resolve(ctx.user_columns, routes)
      assert {SessionAdapter, []} = Router.resolve("global.theme", routes)
    end

    test "an exact per-resource key beats the per-resource wildcard", ctx do
      routes = [
        {"resource:MyApp.PostLive:*", PostAdapter, []},
        {"resource:MyApp.PostLive:columns", ColumnsAdapter, []},
        {"resource.*", GenericAdapter, []}
      ]

      assert {ColumnsAdapter, []} = Router.resolve(ctx.post_columns, routes)
      assert {PostAdapter, []} = Router.resolve(ctx.post_order, routes)
    end

    test "the module name stays one segment, so a same-prefixed module does not leak", ctx do
      # "MyApp.Post" is a dot-prefix of "MyApp.PostLive". Splitting patterns on
      # dots would let a route for one match keys of the other; segmenting with
      # Key.parse/1 keeps the module atomic.
      routes = [
        {"resource:MyApp.Post:*", PostAdapter, []},
        {"resource.*", GenericAdapter, []}
      ]

      post_key = Keys.columns(MyApp.Post)

      assert {PostAdapter, []} = Router.resolve(post_key, routes)
      assert {GenericAdapter, []} = Router.resolve(ctx.post_columns, routes)
    end

    test "a dot-form pattern still covers the whole colon-form resource namespace", ctx do
      routes = [{"resource.*", GenericAdapter, []}, {:default, SessionAdapter, []}]

      assert {GenericAdapter, []} = Router.resolve(ctx.post_columns, routes)
    end
  end

  describe "subtree routing for get_map/3" do
    test "a prefix resolves to the adapter that owns the keys under it" do
      routes = [
        {"resource.*", EctoAdapter, []},
        {:default, Session, []}
      ]

      assert {EctoAdapter, []} = Router.resolve("resource.foo", routes)
      assert {EctoAdapter, []} = Router.resolve("resource.foo.bar", routes)
      assert {Session, []} = Router.resolve("global.sidebar_section", routes)
    end

    test "an exact route on the prefix owns that subtree" do
      routes = [
        {"global.sidebar_section", SectionAdapter, []},
        {"global.*", BroadAdapter, []}
      ]

      assert {SectionAdapter, []} = Router.resolve("global.sidebar_section", routes)
    end

    test "the sidebar_section prefix resolves the same as the keys stored under it" do
      # `Backpex.Preferences.get_map/3` resolves the prefix; the JS writes
      # resolve the individual keys. Both must land in one adapter or a read
      # would miss its own writes.
      routes = [
        {"global.*", SessionAdapter, []},
        {"resource.*", EctoAdapter, []},
        {:default, SessionAdapter, []}
      ]

      prefix = Keys.sidebar_section_prefix()

      assert Router.resolve(prefix, routes) == Router.resolve(prefix <> ".blog", routes)
    end

    test "resolve_subtree/2 includes an exact child route after its wildcard parent" do
      routes = [
        {"global.sidebar_section.blog", BlogAdapter, []},
        {"global.*", SessionAdapter, []}
      ]

      assert Router.resolve_subtree("global.sidebar_section", routes) == [
               {"global.*", SessionAdapter, []},
               {"global.sidebar_section.blog", BlogAdapter, []}
             ]
    end

    test "resolve_subtree/2 excludes a broad wildcard fully shadowed at the requested prefix" do
      routes = [
        {"resource.foo.*", FooAdapter, []},
        {"resource.*", ResourceAdapter, []},
        {:default, SessionAdapter, []}
      ]

      assert Router.resolve_subtree("resource.foo", routes) == [
               {"resource.foo.*", FooAdapter, []}
             ]
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

    test "raises ArgumentError for a function pattern" do
      # Function patterns are not part of the route vocabulary. A config that
      # carries one must fail loudly rather than route by a rule the rest of
      # the system cannot reason about.
      assert_raise ArgumentError, ~r/invalid Backpex.Preferences route pattern/, fn ->
        Router.normalize([{&String.ends_with?(&1, ":columns"), SomeAdapter, []}])
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

    test "accepts nested wildcards in any declaration order" do
      routes = [
        {"resource.foo.*", AdapterA, []},
        {"resource.*", AdapterB, []}
      ]

      assert [_first, _second] = Router.normalize(routes)
      assert [_first, _second] = routes |> Enum.reverse() |> Router.normalize()
    end

    test "accepts a per-resource wildcard alongside the resource catch-all" do
      routes = [
        {"resource:MyApp.PostLive:*", PostAdapter, []},
        {"resource.*", GenericAdapter, []},
        {:default, SessionAdapter, []}
      ]

      assert [_first, _second, _third] = Router.normalize(routes)
    end
  end

  describe "normalize/1 wildcard placement" do
    # An unmatchable wildcard used to normalize cleanly and then match nothing,
    # so the keys it was written for silently went to some other adapter. Every
    # shape that cannot match a key now refuses to boot.
    test "raises for a bare \"*\" and points at :default" do
      assert_raise ArgumentError, ~r/Use :default to match every key/, fn ->
        Router.normalize([{"*", SomeAdapter, []}])
      end
    end

    test "raises for a wildcard that is not the final segment" do
      assert_raise ArgumentError, ~r/invalid Backpex.Preferences wildcard pattern/, fn ->
        Router.normalize([{"resource.*.columns", SomeAdapter, []}])
      end
    end

    test "raises for a wildcard glued to a literal segment" do
      assert_raise ArgumentError, ~r/only valid as the final segment/, fn ->
        Router.normalize([{"res*", SomeAdapter, []}])
      end
    end

    test "raises for a wildcard with an empty leading segment" do
      assert_raise ArgumentError, ~r/invalid Backpex.Preferences wildcard pattern/, fn ->
        Router.normalize([{"resource..*", SomeAdapter, []}])
      end
    end

    test "accepts the wildcard forms the key format can actually produce" do
      routes = [
        {"global.*", A, []},
        {"resource.*", B, []},
        {"resource:MyApp.PostLive:*", C, []},
        {"custom.acme.*", D, []}
      ]

      assert [_a, _b, _c, _d] = Router.normalize(routes)
    end
  end

  defp restore_env(nil), do: Application.delete_env(:backpex, Backpex.Preferences)
  defp restore_env(value), do: Application.put_env(:backpex, Backpex.Preferences, value)
end
