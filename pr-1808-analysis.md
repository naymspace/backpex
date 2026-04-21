# PR #1808 Analysis: Allow defining layout in callback function

## Context

PR #1808 addresses a **compile cycle** in apps using Backpex. When `layout: {MyAppWeb.Layouts, :admin}` is passed to `use Backpex.LiveResource`, it gets stored in `@resource_opts` (a module attribute), creating a compile-time dependency chain:

```
PostLive → DemoWeb.Layouts → DemoWeb (:html) → verified_routes/CoreComponents → DemoWeb.Router → PostLive
```

This cycle means a change to ANY file in it recompiles ALL files — slowing dev feedback loops significantly. The `@resource_opts` is stored in 4 places per LiveResource (the module itself + generated Index, Form, Show submodules).

## Root Cause

In `lib/backpex/live_resource.ex:259`:

```elixir
@resource_opts NimbleOptions.validate!(opts, options_schema)
```

The tuple `{DemoWeb.Layouts, :admin}` stored in a module attribute creates a compile-time dependency on `DemoWeb.Layouts`. This module uses `DemoWeb, :html`, which pulls in `verified_routes()` (referencing `DemoWeb.Router`), and the router references the LiveResource modules — completing the cycle.

## PR's Proposed Solution

1. Makes `layout` option not required
2. Adds a `layout/1` callback to the behavior
3. Default `layout/1` returns `nil`
4. `Backpex.HTML.Layout.layout/1` checks `config(:layout)` first, falls back to callback

## Issues with the PR's Implementation

1. **Silent failure**: Default `layout/1` returns `nil` — if neither option nor callback is set, no layout renders (no error)
2. **Redundant logic**: Calls `config(:layout)` twice in `layout.ex` — once in the `if` guard, once in the `case`
3. **Two code paths**: The `if/else` branching between config and callback is unnecessary complexity
4. **No compile-time guard**: Nothing prevents misconfiguration (no layout option AND no callback override)

## Recommended Improvement

Always route through the callback, with a backwards-compatible default:

```elixir
# Default callback reads from config (existing users unaffected)
@impl Backpex.LiveResource
def layout(_assigns), do: config(:layout)

# layout.ex — single code path, no branching
def layout(assigns) do
  case assigns.live_resource.layout(assigns) do
    {module, fun} -> apply(module, fun, [assigns])
    fun when is_function(fun, 1) -> fun.(assigns)
  end
end
```

This is simpler (single path), backwards compatible, and fails fast on misconfiguration via pattern match rather than silently rendering nothing.

## Other Options That Could Cause This Issue

**`layout` is the primary offender** because it's the only option that typically references web-layer modules (Layouts → CoreComponents → Router → LiveResource). Other options:

| Option | Risk | Why |
|--------|------|-----|
| `layout` | **High** | References web-layer modules that depend on the router |
| `on_mount` | Low | Could cause cycles if hooks depend on web modules, but uncommon |
| `adapter_config` (schema, repo) | None | App-layer modules don't depend on the web layer |
| `pubsub` | None | PubSub modules don't depend on the web layer |

## Alternative Approaches Considered

| Approach | Pros | Cons |
|----------|------|------|
| **Callback (improved)** | Simple, non-breaking, familiar pattern | Two ways to set layout |
| **Transparent macro fix** (extract layout from `@resource_opts`, inject into function body) | Fixes for everyone without code changes | Complex macro refactor across 4 `@resource_opts` sites, fragile with `bind_quoted` |
| **Breaking change** (remove option, always use callback) | Cleanest single approach | Migration burden for all users |
| **Wrap in zero-arity fn** (`layout: fn -> {Mod, :fun} end`) | Minimal change | Doesn't work — fn literal in module attribute still creates compile dep |

## Deep Dive: Transparent Macro Fix

The idea: extract the layout from `opts` *before* it enters any module attribute (`@resource_opts`), and inject it into a function body instead. This fixes the compile cycle for ALL users without requiring code changes.

### The Challenge

The `__using__` macro uses `bind_quoted`, which prevents `unquote` inside the block. So we can't simply extract a variable and inject it into a `def` body within the same block. Additionally, `config/1` is defined as a single catch-all clause — we can't split it across separate `quote` blocks because Elixir requires function clauses to be contiguous.

### The Approach: Hybrid Macro

Split the macro return value into two parts:
1. A `bind_quoted` block (everything except layout storage) — layout stripped from opts
2. A separate `quote` block that defines a layout accessor using `unquote` (runtime dep only)

```elixir
# lib/backpex/live_resource.ex

defmacro __using__(opts) do
  # Step 1: At macro expansion time, capture and escape the layout value.
  # Macro.escape turns it into an AST literal — it won't be evaluated
  # until it's placed inside a function body via unquote.
  layout_escaped = Macro.escape(Keyword.get(opts, :layout))

  # Step 2: The main bind_quoted block — layout stripped from @resource_opts
  main_ast = quote bind_quoted: [opts: opts, options_schema: @options_schema] do
    @before_compile Backpex.LiveResource
    @behaviour Backpex.LiveResource

    # Make layout optional for storage, but validate full opts first
    relaxed_schema = Keyword.update!(options_schema, :layout, &Keyword.put(&1, :required, false))
    opts_without_layout = Keyword.delete(opts, :layout)

    # Validate full opts (catches user errors), but STORE without layout
    NimbleOptions.validate!(opts, options_schema)
    @resource_opts NimbleOptions.validate!(opts_without_layout, relaxed_schema)

    @adapter_opts @resource_opts[:adapter].validate_config!(@resource_opts[:adapter_config])

    use BackpexWeb, :html
    import Backpex.LiveResource
    import Phoenix.LiveView.Helpers
    alias Backpex.LiveResource
    require Backpex

    # Note: config(:layout) will return nil — layout is accessed via __backpex_layout__/0
    def config(key), do: Keyword.get(@resource_opts, key)
    def adapter_config(key), do: Keyword.get(@adapter_opts, key)
    def pubsub, do: LiveResource.pubsub(__MODULE__)
    def fields(live_action, assigns), do: LiveResource.fields(__MODULE__, live_action, assigns)

    # ... all the @impl callbacks, defoverridable, etc. (unchanged)

    live_resource = __MODULE__

    for action <- ~w(Index Form Show)a do
      defmodule String.to_atom("#{__MODULE__}.#{action}") do
        # Also store WITHOUT layout — avoids compile dep in submodules too
        @resource_opts NimbleOptions.validate!(opts_without_layout, relaxed_schema)

        use Phoenix.LiveView
        @action_module String.to_existing_atom("Elixir.Backpex.LiveResource.#{action}")
        insert_on_mount_hooks(@resource_opts[:on_mount])

        def mount(params, session, socket), do: @action_module.mount(params, session, socket, unquote(live_resource))
        def handle_params(params, url, socket), do: @action_module.handle_params(params, url, socket)
        def render(assigns), do: @action_module.render(assigns)
        def handle_info(msg, socket), do: @action_module.handle_info(msg, socket)
        def handle_event(event, params, socket), do: @action_module.handle_event(event, params, socket)
      end
    end
  end

  # Step 3: Define layout accessor OUTSIDE bind_quoted — uses unquote
  # to place the layout value in a function body (runtime dep, not compile dep)
  layout_ast = quote do
    @doc false
    def __backpex_layout__, do: unquote(layout_escaped)
  end

  # Step 4: Combine both ASTs into a single block
  {:__block__, [], [main_ast, layout_ast]}
end
```

Then update the single callsite in `layout.ex`:

```elixir
# lib/backpex/html/layout.ex

def layout(assigns) do
  case assigns.live_resource.__backpex_layout__() do
    {module, fun} -> apply(module, fun, [assigns])
    fun when is_function(fun, 1) -> fun.(assigns)
  end
end
```

### Why This Works

| What | Where | Dependency type |
|------|-------|----------------|
| `@resource_opts` (without layout) | Module attribute | No layout dep |
| `__backpex_layout__/0` body | Function body via `unquote` | **Runtime** dep only |
| Submodule `@resource_opts` | Module attribute | No layout dep (stripped) |

The `Macro.escape` + `unquote` pattern is the key: `Macro.escape` converts the value `{DemoWeb.Layouts, :admin}` into an AST representation at macro expansion time. When `unquote` places it inside `def __backpex_layout__`, it becomes a literal in the function body — the compiler sees it as a runtime reference, not a compile-time one.

### Trade-offs

**Pros:**
- Zero user-facing changes — existing `layout: {Mod, :fun}` syntax works as-is
- Fixes compile cycle for ALL users transparently
- No new callbacks or dual configuration paths
- Submodules also fixed (they use `opts_without_layout`)

**Cons:**
- More complex macro code (hybrid `bind_quoted` + raw `quote`)
- `config(:layout)` returns `nil` — technically a behavior change, but it's only called internally in `layout.ex` (verified via grep)
- Double NimbleOptions validation (full opts for error checking, stripped opts for storage)
- Need to verify `NimbleOptions.validate!` with the full opts doesn't itself create the compile dep (if it does `:mod_arg` validation by calling `Code.ensure_compiled`)

### Open Risk: NimbleOptions Validation

The line `NimbleOptions.validate!(opts, options_schema)` validates the full opts *including* layout. If NimbleOptions' `:mod_arg` type validation calls `Code.ensure_compiled` or similar on the module, this line alone creates the compile dependency — even though we don't store the result.

If this is the case, we'd need to either:
1. Skip validation of the full opts (just validate `opts_without_layout`)
2. Use a custom validator for layout that doesn't trigger module loading
3. Validate layout manually: `is_tuple(layout) and tuple_size(layout) == 2`

This risk makes the callback approach (PR #1808, improved) the safer bet in practice, since it avoids the layout entering the macro entirely when the user opts into the callback.

## Conclusion

The PR correctly identifies a real compile cycle problem and the callback approach is the right direction. The implementation should be improved to use a single code path through the callback with a sensible default (`config(:layout)`), rather than the dual `if/else` approach with a `nil` default.

The transparent macro fix is theoretically cleaner (no user changes, no dual config) but carries risk around NimbleOptions validation behavior and adds macro complexity. It could be explored as a follow-up if the callback approach proves insufficient.
