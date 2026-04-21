# PR #1749 — Review Findings

> **PR:** [#1749 — Add user preferences system with pluggable storage adapters](https://github.com/naymspace/backpex/pull/1749)
> **Branch:** `feature/user-preference-system` → `feature/collapsible-sidebar`
> **Scope:** +2820 / −575 across 43 files · breaking change · slated for v0.19
>
> Findings consolidated from four parallel reviewers (user-perspective, Elixir code smell, test engineer, architect) plus five pre-existing copilot inline comments. Each item below is **self-contained** — a fix agent does not need to read the whole PR to act on it.

## How to read this file

- **Sections are severity-ordered.** Blockers first, then Majors, then Minors, then Decision Points, then Copilot cross-check.
- **Each finding has:** `ID` for cross-reference · `Files` with `path:line` anchors · `Problem` (what's wrong) · `Fix` (what to change) · `Verify` (how to confirm the fix).
- **Decision Points** are intentionally not actionable — they need a human call before any code change.
- **Fix order dependency:** B1 → B8 (test depends on fix), B2 is independent, B4 → B6 are all docs. Most items are independent and can be parallelized.

---

## Blockers

### B1 · `put_batch/3` atomicity claim is structurally unachievable

- **Files:** [lib/backpex/preferences.ex:157-174](../lib/backpex/preferences.ex), [guides/live_resource/user-preferences.md](../guides/live_resource/user-preferences.md), [lib/backpex/controllers/preferences_controller.ex:26-28](../lib/backpex/controllers/preferences_controller.ex)
- **Problem:** The dispatcher is documented as "all-or-nothing across adapters," but the current loop keeps calling `module.put/4` even after an adapter returns `{:error, reason}` (copilot #3), AND there is no rollback primitive on the adapter behaviour. If an eager adapter (e.g. an Ecto adapter returning `{:ok, [:noop]}`) commits `Repo.insert!` during entry 1 and entry 2 errors, entry 1 is already written. Swapping to `Enum.reduce_while/3` prevents further writes but cannot undo the commit.
- **Fix:** Pick one of two paths (see Decision Point D1 for guidance):
  - **Path A — walk back the claim (cheap):** `Enum.reduce_while/3` to short-circuit on first error, update every doc (moduledoc on `Backpex.Preferences`, docstring on `put_batch/3`, `PreferencesController` moduledoc, guide) to read "best-effort, first-error-wins; earlier writes may have committed."
  - **Path B — make it true (honest):** Introduce a two-phase callback on `Backpex.Preferences.Adapter`: `c:prepare/4` → `{:ok, token} | {:error, reason}`; `c:commit/1` → `{:ok, [side_effect]}`; `c:rollback/1` → `:ok`. Dispatcher runs `prepare` for every entry first; on any error, calls `rollback` on prior tokens. Session adapter's `prepare` validates + returns the `:put_session` tuple as the token; Ecto adapter wraps in `Repo.transaction`.
- **Verify:** Add the integration test described in **B8** (below). The test must fail under the current code and pass after the fix.

### B2 · `get_map/3` silently routes prefix lookups to the wrong adapter

- **Files:** [lib/backpex/preferences/router.ex:68-78](../lib/backpex/preferences/router.ex), [lib/backpex/preferences.ex:88](../lib/backpex/preferences.ex)
- **Problem:** `Backpex.Preferences.get_map(ctx, "resource.foo", _opts)` calls `Router.resolve("resource.foo")` which treats the argument as a **key**, not a **prefix**. Config like
  ```elixir
  adapters: [
    {"resource.foo.*", MyApp.EctoAdapter, repo: MyApp.Repo},
    {:default,         Backpex.Preferences.Adapters.Session, []}
  ]
  ```
  makes `get_map(ctx, "resource.foo")` fall through to Session because `Key.match?("resource.foo.*", "resource.foo")` returns `false` — the pattern is narrower than the lookup.
- **Fix:** Add `Router.resolve_prefix/1` (or pass a `:prefix_lookup` flag to `resolve/1`). Semantics: "which adapter is responsible for keys **under** this prefix?" If two configured patterns disagree about the subtree, either raise `ArgumentError` at config time (preferred) or pick the most specific and log a warning. Update `Backpex.Preferences.get_map/3` to call the new function.
- **Verify:** Test fixture with `{"resource.foo.*", EctoAdapter}` + `{:default, Session}`; assert `get_map(ctx, "resource.foo")` dispatches to `EctoAdapter`.

### B3 · Socket-origin `put_async` silently drops `:put_session` side effects

- **Files:** [lib/backpex/preferences.ex:133-137](../lib/backpex/preferences.ex), [lib/backpex/preferences.ex:232-237](../lib/backpex/preferences.ex)
- **Problem:** `apply_effects_on_socket/2` pattern-matches `{:put_session, _k, _v}` and throws it away. The current Session adapter returns `:requires_http` on socket origin so nothing triggers the drop today, but the behaviour's contract permits any adapter to emit `:put_session` from a socket call. A third-party adapter will have its write vanish with no error, no log, no telemetry.
- **Fix:** Either (a) make the type signature reject `:put_session` in socket origin (separate behaviour or a `source`-aware effect whitelist), or (b) re-route `{:put_session, _, _}` from a socket through `push_event_fallback/3` the same way `:requires_http` is handled. Option (b) is simpler and keeps the adapter contract uniform. Add a `Logger.warning/1` on the drop path regardless.
- **Verify:** Unit test: fake adapter that returns `{:ok, [{:put_session, "k", %{a: 1}}]}` on socket origin; assert a `push_event` was queued (or a warning logged).

### B4 · `BackpexPreferences` JS recipe for `custom.*` is aspirational end-to-end

- **Files:** [guides/live_resource/user-preferences.md:516-521](../guides/live_resource/user-preferences.md), [assets/js/hooks/index.js](../assets/js/hooks/index.js), [priv/static/js/backpex.esm.js:3651](../priv/static/js/backpex.esm.js)
- **Problem:** Copilot #1 flagged the import form. Confirmed stronger: the compiled bundle only exports `Hooks`; `BackpexPreferences` is a module-internal object. An app following the "Writing from the browser" section hits a runtime undefined. There is **no** documented way today for app JS to persist a `custom.*` preference.
- **Fix:** Pick one:
  - **Export the helper.** In [assets/js/hooks/_preferences.js](../assets/js/hooks/_preferences.js), ensure `BackpexPreferences` is a named export. Re-export from [assets/js/hooks/index.js](../assets/js/hooks/index.js) or a new `assets/js/index.js`. Rebuild `priv/static/js/backpex.{esm,cjs}.js`. Keep the guide's recipe as-is.
  - **Rewrite the recipe.** Drop the `BackpexPreferences.set(...)` example; replace with a LiveView-hook pattern: JS dispatches a `phx-click` / `pushEvent`, a user-written `handle_event/3` calls `Backpex.Preferences.put_async/4`.
- **Verify:** The recipe as written must work when copy-pasted into an app's `app.js`. Alternative recipe must compile and hit the controller.

### B5 · Demo app contradicts its own upgrade guide

- **Files:** [demo/lib/demo_web/plugs/theme_plug.ex](../demo/lib/demo_web/plugs/theme_plug.ex), [demo/lib/demo_web/router.ex:14](../demo/lib/demo_web/router.ex), [guides/upgrading/v0.19.md:138-171](../guides/upgrading/v0.19.md)
- **Problem:** The upgrade guide tells users to remove the old `ThemeSelectorPlug` and rely on `Backpex.InitAssigns` for `@current_theme`. The demo app does the opposite: `DemoWeb.ThemePlug` still reads `session["backpex"]["theme"]` and assigns `:theme`, and `router.ex:14` still wires it into the pipeline. An integrator diffing the demo to verify their migration is actively misled.
- **Fix:** Remove [demo/lib/demo_web/plugs/theme_plug.ex](../demo/lib/demo_web/plugs/theme_plug.ex). Remove the `plug DemoWeb.ThemePlug` line from [demo/lib/demo_web/router.ex:14](../demo/lib/demo_web/router.ex). Confirm root layout uses `@current_theme` not `assigns[:theme]`. Run the demo locally, toggle the theme, reload, verify `<html data-theme>` persists.
- **Verify:** `grep -rn "ThemePlug\|assigns\[:theme\]" demo/` returns nothing.

### B6 · Recipe A ships a broken struct-construction snippet

- **Files:** [guides/live_resource/user-preferences.md:342-343](../guides/live_resource/user-preferences.md)
- **Problem:** The recipe contains
  ```elixir
  %UserPreference{}
  |> UserPreference.__struct__()
  |> Map.put(:user_id, user_id)
  |> Map.put(:key, key)
  |> Map.put(:value, wrap_value(value))
  |> repo.insert!(...)
  ```
  The piped `__struct__/0` call discards the literal and rebuilds an empty struct — at best redundant, at worst confusing. A reader copy-pasting gets a working-but-ugly snippet.
- **Fix:** Replace with either a direct literal `%UserPreference{user_id: user_id, key: key, value: wrap_value(value)}` or a proper `UserPreference.changeset/2` + `repo.insert!`. Prefer the changeset form — it's what a production app would actually write.
- **Verify:** Paste the new snippet into an `iex` session with a stub schema; it must compile and insert.

### B7 · No LiveView integration test for `persist:` — the PR's headline feature

- **Files:** [test/preferences/](../test/preferences/), [lib/backpex/live_resource/index.ex:395-613](../lib/backpex/live_resource/index.ex)
- **Problem:** Nothing in the test suite imports `Phoenix.LiveViewTest` or exercises a LiveResource mounted with `persist: [:order, :filters, :columns]`. The write-side of the feature — `maybe_persist_order`, `maybe_persist_filters`, `maybe_push_columns`, the hard-coded `"backpex:set_preference"` push_event name — is entirely uncovered end-to-end. A regression that breaks `handle_params` writes or changes the event payload shape ships silently.
- **Fix:** Add a test file under [demo/test/](../demo/test/) (needs the full Phoenix app to host a LiveResource):
  ```
  demo/test/demo_web/live/preferences_persistence_test.exs
  ```
  Test matrix: `persist: []` (default — URL-only), `persist: [:order]`, `persist: [:filters]`, `persist: [:columns]`. For each, mount the LiveResource, trigger the change (sort click, filter apply, column toggle), assert the expected `"backpex:set_preference"` push_event was emitted with the expected key/value, then re-mount and assert the state was restored.
- **Verify:** `mix test demo/test/demo_web/live/preferences_persistence_test.exs` green. Delete one of the `maybe_persist_*` calls in `index.ex` — the new test must fail.

### B8 · Copilot #3's existing test doesn't catch the bug it describes

- **Files:** [test/controllers/preferences_controller_test.exs:111-151](../test/controllers/preferences_controller_test.exs), [test/support/in_memory_preferences_adapter.ex:87-93](../test/support/in_memory_preferences_adapter.ex)
- **Problem:** The current atomicity test uses `"global.theme"` (Session, `:controller` source → always returns `{:ok, [put_session ...]}`) alongside `RejectingAdapter`. On batch failure the controller never calls `apply_effects_on_conn`, so the session is untouched regardless of whether `put_batch/3` short-circuits. The test passes under both buggy and fixed implementations.
- **Fix:** Add a test where one entry routes to `InMemoryPreferencesAdapter` (writes to ETS eagerly, line 87-93) and a later entry routes to `RejectingAdapter`. After the batch, assert `InMemoryPreferencesAdapter` has no rows. This test must fail under the current `Enum.reduce/3` code and pass after **B1** is fixed (by any path).
- **Verify:** Test fails before B1 fix, passes after.

### B9 · `Backpex.Preferences.put_async/4` has zero test coverage

- **Files:** [test/preferences_test.exs](../test/preferences_test.exs), [lib/backpex/preferences.ex:118-138](../lib/backpex/preferences.ex)
- **Problem:** Both the `%Plug.Conn{}` branch and the `%Phoenix.LiveView.Socket{}` branch are untested. The `{:error, :requires_http} -> push_event_fallback/3` path — the single most important control-flow in the module — is never asserted. A rename of the `"backpex:set_preference"` event name would pass the whole suite.
- **Fix:** In [test/preferences_test.exs](../test/preferences_test.exs), add `describe "put_async/4"` with cases for:
  1. `%Plug.Conn{}` origin, Session adapter → assert `get_session(conn, "backpex")` reflects the write.
  2. `%Phoenix.LiveView.Socket{}` origin, Session adapter (which returns `:requires_http`) → assert a `push_event` for `"backpex:set_preference"` with the right key/value is queued.
  3. Adapter raises → `{:error, _}` returned, no crash.
  4. `:unidentified` identity → write is rejected with the right error shape.
- **Verify:** Renaming `"backpex:set_preference"` to anything else anywhere in the module now makes the suite fail.

---

## Majors

### M1 · Identity "memoization" is single-call, not per-session

- **Files:** [lib/backpex/preferences.ex:200-205](../lib/backpex/preferences.ex), [lib/backpex/preferences/context.ex](../lib/backpex/preferences/context.ex)
- **Problem:** The docstring and PR body claim "resolver runs once per context, cached on `ctx.identity`." In practice, the context is rebuilt on every `put_async` / `get` / `get_map` call (`from_mount`, `from_conn`, `from_socket` all start with `identity: nil`), so the resolver runs per-call, not per-session. The memoization window is a single function execution.
- **Fix:** Either (a) drop the memoization claim from docstring + PR body and acknowledge per-call resolution, or (b) stash the resolved identity on `socket.assigns[:backpex_identity]` in an `on_mount` step and thread it through new `from_mount`/`from_socket` builders so subsequent calls skip resolution. Option (b) is more work but honors the original claim.
- **Verify:** Counter on a mock resolver; assert it's called once per mount regardless of how many `put_async` calls happen.

### M2 · `put_async/4` is misnamed — nothing is async inside

- **Files:** [lib/backpex/preferences.ex:114-138](../lib/backpex/preferences.ex)
- **Problem:** The function runs `dispatch_put` synchronously, returns `{:ok, socket_or_conn}` inline. The "async" label reflects browser-side keepalive fetch semantics that aren't visible at this API. A future reader grepping for `Task` or `spawn` will be confused.
- **Fix:** Rename to `put/4` (mirrors `Map.put/3`, `Plug.Conn.put_session/3`) or `put_from/4` (hints at "side-effecting write via caller"). Deprecate `put_async/4` with `@deprecated "use put/4"` in a minor version, then remove. **Check all call sites** and update the guide and moduledoc.
- **Verify:** `grep -rn "put_async" lib/ test/ guides/ demo/` returns zero results after full rename (or only deprecation wrappers).

### M3 · Side-effect protocol encodes Session semantics into the abstraction

- **Files:** [lib/backpex/preferences/adapter.ex:49-55](../lib/backpex/preferences/adapter.ex), [lib/backpex/preferences.ex:232-237](../lib/backpex/preferences.ex)
- **Problem:** The behaviour's side-effect vocabulary is `{:put_session, key, map} | :noop`. `:put_session` is Session-specific — an Ecto adapter has no legitimate side effect it can name. The protocol doesn't abstract side effects; it abstracts session writes specifically.
- **Fix (two viable shapes — pick in D2):**
  - **Struct + namespaced actions:** `%Backpex.Preferences.Effect{action: :put_session, key: k, value: v}`. Clear type, future actions added as new struct fields or a tagged union.
  - **Invert ownership:** Adapter owns its persistence; returns `:ok | {:defer, (conn -> conn)} | {:error, _}`. Session adapter defers (its fun captures `Plug.Conn.put_session/3`); Ecto adapter persists and returns `:ok`. Dispatcher applies the `{:defer, fun}` or falls back to `push_event` on socket origin.
- **Verify:** A new second real adapter (Ecto or PubSub) must slot in without extending the core vocabulary.

### M4 · Zero `Logger` or telemetry on any error path

- **Files:** [lib/backpex/preferences.ex:63-72,200-205,247-271](../lib/backpex/preferences.ex), [lib/backpex/preferences/adapters/session.ex](../lib/backpex/preferences/adapters/session.ex), [lib/backpex/controllers/preferences_controller.ex:55-58](../lib/backpex/controllers/preferences_controller.ex)
- **Problem:** The identity resolver's `rescue _ -> :unidentified` and every `{:error, _} -> default` fallthrough is silent. If the resolver raises `DBConnection.ConnectionError`, every user silently falls back to anonymous, reads return defaults, writes fail with `{:error, :unidentified}`. A production operator has no signal.
- **Fix:** Add `Logger.warning/1` (or `Logger.error/1` for unexpected failures) at every `rescue`, `catch`, and `{:error, _}` swallow point in `Backpex.Preferences` and `PreferencesController`. Ideally also a `:telemetry.execute/3` event at `[:backpex, :preferences, :error]` with metadata (adapter, key, reason). Document the event list in the guide.
- **Verify:** Configure a test `Logger` backend; assert a warning is emitted when a resolver raises.

### M5 · `Backpex.InitAssigns` has zero test coverage — regression from deleted test

- **Files:** [lib/backpex/init_assigns.ex](../lib/backpex/init_assigns.ex), deleted [test/plugs/theme_selector_plug_test.exs](../test/plugs/theme_selector_plug_test.exs)
- **Problem:** The deleted plug test covered three scenarios (missing backpex key, missing theme key, present theme). `InitAssigns` is its functional replacement and has no tests. None of `assign_current_theme`, `assign_sidebar_open`, `assign_sidebar_section_states`, or `attach_current_url_hook` are exercised.
- **Fix:** Create [test/init_assigns_test.exs](../test/init_assigns_test.exs). Cover: (a) empty session → defaults (`"light"`, `true`, `%{}`); (b) present values → assigned correctly; (c) malformed session data → safe defaults without crashing; (d) custom theme via preferences adapter.
- **Verify:** Flip a default value in `init_assigns.ex`; the new test must fail.

### M6 · Copilot #3 fix exposes a second gap: hard-coded key strings never asserted

- **Files:** [test/controllers/preferences_controller_test.exs](../test/controllers/preferences_controller_test.exs), [lib/backpex/init_assigns.ex](../lib/backpex/init_assigns.ex), [lib/backpex/live_resource/index.ex](../lib/backpex/live_resource/index.ex)
- **Problem:** Tests use strings like `"global.theme"` and `"resource:Mod:columns"` directly. Nothing asserts that the live code in `InitAssigns` or `Index` emits those same strings. A rename (`"global.theme"` → `"global.color_scheme"`) in production code would pass the entire suite while silently breaking every existing user's stored session.
- **Fix:** Introduce a module attribute or small module `Backpex.Preferences.Keys` exposing each key as a named function (`theme/0`, `sidebar_open/0`, `columns/1`, `order/1`, `filters/1`, `metrics_visible/1`). Replace the string literals across `InitAssigns`, `Index`, controllers, and tests. The test that writes `"global.theme"` becomes a test that writes `Backpex.Preferences.Keys.theme()`.
- **Verify:** `grep -rn '"global\.' lib/` returns zero results; same for `"resource:`.

### M7 · `LiveResource.Index` hard-codes `"backpex:set_preference"` in five places

- **Files:** [lib/backpex/live_resource/index.ex:11,302,306,398,592,612](../lib/backpex/live_resource/index.ex), [lib/backpex/preferences.ex](../lib/backpex/preferences.ex)
- **Problem:** The JS-contract event name is duplicated across multiple call sites. No single seam, no test coverage on the emitted shape. If the JS contract changes, sites drift.
- **Fix:** Extract `Backpex.Preferences.LiveView.push_write(socket, key, value)` (or `Backpex.Preferences.push_from_socket/3`). Move the event name to a module attribute in that module. Replace all five call sites. Ties into **M6** (key naming).
- **Verify:** `grep -rn "backpex:set_preference" lib/` returns exactly one match (the new helper).

### M8 · Recipe B (prefix → column mapping) ships half-finished

- **Files:** [guides/live_resource/user-preferences.md:430](../guides/live_resource/user-preferences.md)
- **Problem:** The recipe stops at `# get_map/3, put/4 follow the same "which column?" lookup.` Recipe A takes ~80 lines for these; Recipe B leaves the reader to write them from scratch. A "here's the idea, figure it out" pattern in a how-to is a regression from Recipe A's explicitness.
- **Fix:** Either (a) complete Recipe B with fully-worked `get_map/3` and `put/4` implementations, or (b) drop Recipe B and add a shorter "when you already have a typed settings table, adapt Recipe A by replacing the k/v schema — see the `ash_backpex` community example" note.
- **Verify:** A user can copy the guide and compile without writing additional code (for option a), or the guide no longer makes a claim it doesn't deliver (for option b).

### M9 · Upgrade guide lacks runtime-vs-compile-time failure guidance

- **Files:** [guides/upgrading/v0.19.md](../guides/upgrading/v0.19.md)
- **Problem:** Every theme/sidebar assign mistake fails silently at render, not at compile. Missing `@current_theme` → `nil` → falls back to `"light"`. Missing `@sidebar_open` → renders closed. A user skipping step 2 or step 4 thinks the migration worked.
- **Fix:** Add a "Symptoms of a skipped step" table at the top of the Preferences section: step → observable symptom → where to look. Or a shorter note: "All assigns in this migration fail at render, not at compile — verify in the browser after each step."
- **Verify:** A new user skipping step 4 should be able to find the symptom ("sidebar renders closed after toggle survives reload") in the guide.

### M10 · Router edge cases untested

- **Files:** [test/preferences/router_test.exs](../test/preferences/router_test.exs), [lib/backpex/preferences/router.ex](../lib/backpex/preferences/router.ex)
- **Problem:** Missing coverage for:
  - Tie-break between two equal-length wildcard patterns (`"resource.*"` vs `"global.*"`).
  - `Router.resolve/1` zero-config path (test only exercises `routes/0`).
  - Malformed entries (e.g. `{"foo.*", :not_a_module}`) raising `FunctionClauseError` with no friendly message.
  - A non-`:default`, non-wildcard longest pattern beating a wildcard at a different depth.
- **Fix:** Add tests for each. For malformed entries, add a `normalize/1` clause that raises `ArgumentError` with a clear message.
- **Verify:** Add `{"foo.*", :not_a_module}` to config in a test; assert `ArgumentError` with a message mentioning the malformed entry.

### M11 · Key parsing corner cases untested

- **Files:** [test/preferences/key_test.exs](../test/preferences/key_test.exs), [lib/backpex/preferences/key.ex](../lib/backpex/preferences/key.ex)
- **Problem:** No tests for: `"Elixir.Foo.Bar:suffix"` (colon form wins), trailing colon `"resource:Foo:"` (produces empty segment), leading colon `":foo"`, mixed form `"resource.MyApp:columns"`, empty string, unicode module names.
- **Fix:** Add a test for each. Document the colon-over-dot precedence rule explicitly in the module's `@moduledoc` with examples.
- **Verify:** Running `mix test test/preferences/key_test.exs` gives coverage of the parse-format matrix.

---

## Minors

### m1 · `put_batch/3` effect accumulation is O(n²) (copilot #4)

- **Files:** [lib/backpex/preferences.ex:163-169](../lib/backpex/preferences.ex)
- **Problem:** `effects_acc ++ fx` inside `Enum.reduce/3` is quadratic in batch size.
- **Fix:** After B1 is applied, the `reduce_while` form will naturally use prepend + `Enum.reverse/1` at the end. If B1 Path A (walk back) is chosen, make sure this fix lands in the same commit.
- **Verify:** Benchmark with a 100-entry batch — should be sub-millisecond.

### m2 · `sidebar_section` lies about auto-populating `sidebar_section_states` (copilot #5)

- **Files:** [lib/backpex/html/layout.ex:503-511](../lib/backpex/html/layout.ex)
- **Problem:** The docstring says "populated automatically from assigns if not provided" but the component just defaults to `%{}`. Parent assigns are never consulted.
- **Fix:** Add `assigns = assign_new(assigns, :sidebar_section_states, fn -> %{} end)` at the top of the function body. Updates docstring to match.
- **Verify:** Mount a component tree where the parent assigns `:sidebar_section_states` but the child doesn't pass it — child should see the parent value.

### m3 · `toggle_columns_inputs/1` declares unused `attr :live_resource` (copilot #2)

- **Files:** [lib/backpex/html/resource.ex:575-589](../lib/backpex/html/resource.ex)
- **Problem:** The attr is `required: true` but `@live_resource` is never referenced in the component body.
- **Fix:** Remove the attr and remove the pass-through from any caller of `toggle_columns_inputs/1`. Alternative: use `@live_resource` for `Backpex.__(...)` translation of labels, but current labels come from field config.
- **Verify:** `grep -rn "toggle_columns_inputs" lib/` shows all call sites updated.

### m4 · `Context` has dead `conn` field leaking Plug into adapters

- **Files:** [lib/backpex/preferences/context.ex:32-40](../lib/backpex/preferences/context.ex)
- **Problem:** Only `from_conn` itself reads `conn`; no adapter consumes it. The field leaks Plug dependency into every adapter call signature.
- **Fix:** Drop `conn` from the struct. Keep `source` as the discriminator. Update `from_conn/1` to extract session + assigns and discard the conn.
- **Verify:** `grep -rn "ctx.conn" lib/ test/` returns zero results.

### m5 · `Context.coerce/1` accepts any map (too permissive)

- **Files:** [lib/backpex/preferences/context.ex:79-81](../lib/backpex/preferences/context.ex)
- **Problem:** A random map accidentally passed becomes `from_mount(that_map)`. Silently handles bad input.
- **Fix:** Narrow the guard: `is_map(session) and not is_struct(session)` plus a check that all keys are binaries (session shape).
- **Verify:** Passing a malformed map now raises `FunctionClauseError` or returns a clear error.

### m6 · `get/3` swallows `{:error, _}` indistinguishably from `:not_found`

- **Files:** [lib/backpex/preferences.ex:63-72](../lib/backpex/preferences.ex)
- **Problem:** Adapter exception and missing key return the same value (`default`). Caller has no way to distinguish.
- **Fix:** Add `fetch/3` returning `{:ok, value} | :error | {:error, reason}` for callers needing the distinction. `get/3` keeps current shape but adds `Logger.warning` on unexpected error (dovetails with **M4**).
- **Verify:** A test that forces an adapter to raise should see a `Logger.warning` via capture_log.

### m7 · `Key.parse/1` dual-separator rule is ambient

- **Files:** [lib/backpex/preferences/key.ex:41-47](../lib/backpex/preferences/key.ex)
- **Problem:** Presence of `:` anywhere flips the whole key to colon-split. A custom key with a stray `:` changes parsing silently.
- **Fix:** Document the precedence in the docstring with examples covering the sharp edges. Alternatively, normalize at write time — reject keys with ambiguous separators in a `Key.build/1` helper that the index and controller both route through.
- **Verify:** Docstring has executable examples covering `"custom.bad:key"`.

### m8 · Router `specificity/1` uses magic numbers

- **Files:** [lib/backpex/preferences/router.ex:99-108](../lib/backpex/preferences/router.ex)
- **Problem:** Exact match → 100; wildcards → `len*10 - 1`. Works for 2-3 segments; fragile if nesting deepens.
- **Fix:** Replace with a tuple sort: `{exact_match?, length, not_wildcard?}` — clearer and monotonic. Add a doctest showing the ordering.
- **Verify:** Doctest covers: `specificity(parse("global.*")) < specificity(parse("global.theme"))`.

### m9 · Controller returns 200 on batch error — fights HTTP conventions

- **Files:** [lib/backpex/controllers/preferences_controller.ex:55-58](../lib/backpex/controllers/preferences_controller.ex)
- **Problem:** Returning 200 with `{ok: false}` on `{:error, errors}` is intentional but weak from an ops perspective.
- **Fix:** Change the batch-error response to 422 with the same JSON body. The JS client doesn't care about the status (it parses `ok`). Ops dashboards now show the errors.
- **Verify:** Existing controller test asserts status 200; update to 422. The JS hook at [assets/js/hooks/_preferences.js](../assets/js/hooks/_preferences.js) doesn't need changes.

### m10 · No doctests on public dispatcher API

- **Files:** [lib/backpex/preferences.ex](../lib/backpex/preferences.ex), [lib/backpex/preferences/router.ex](../lib/backpex/preferences/router.ex)
- **Problem:** `Preferences.get/3`, `get_map/3`, `put_async/4`, `put_batch/3`, `Router.resolve/1` — none have executable doctests. The "105 doctests" in the PR body is a library-wide total.
- **Fix:** Add doctests for the sunny-path shape of each public function, plus the most important error case. Keep them short — a doctest documents intent.
- **Verify:** `mix test --only doctest` catches any drift.

### m11 · Arity/prose mismatches in user-preferences guide

- **Files:** [guides/live_resource/user-preferences.md:524,530,536](../guides/live_resource/user-preferences.md)
- **Problem:** Guide says `put_async/3` three times. Actual arity is `/4` (opts is the fourth arg with default `[]`).
- **Fix:** s/put_async\/3/put_async\/4/g. If **M2** (rename) lands, use the new name throughout.
- **Verify:** `grep -n "put_async" guides/live_resource/user-preferences.md` — every occurrence matches the actual arity.

### m12 · Installation guide lists assigns without pointing to their source

- **Files:** [guides/get_started/installation.md:140-195,341](../guides/get_started/installation.md)
- **Problem:** Layout example uses `@sidebar_open` and `@sidebar_section_states`; `Backpex.InitAssigns` is only mentioned 200+ lines later.
- **Fix:** In the layout example block, add a cross-link: "These assigns are populated by `Backpex.InitAssigns` — see [Add resource routes](#add-resource-routes) for setup." Or restructure so routing comes before the layout example.
- **Verify:** A reader following the guide top-to-bottom can resolve every `@assign` they see.

---

## Decision Points

These require a human call before any code work. Each has two defensible answers; pick one.

### D1 · Atomicity guarantee for `put_batch/3` (resolves B1)

- **Option A — walk back the claim.** Small change, honest documentation. Update `Backpex.Preferences.put_batch/3` docstring and guide to read "best-effort, first-error-wins; earlier writes may have committed." Fix `reduce_while` (m1) for clean first-error semantics.
- **Option B — make it true.** Add `c:prepare/4 → {:ok, token}`, `c:commit/1 → {:ok, [effects]}`, `c:rollback/1 → :ok` to the adapter behaviour. Reference implementation updates for Session and `InMemoryPreferencesAdapter`. Larger scope but the only honest fix across heterogeneous backends.

Recommendation from reviewers: **Option A** for v0.19, plan Option B for a later version once a real Ecto adapter ships in-tree.

### D2 · Side-effect protocol shape (resolves M3)

- **Option X — struct + namespaced actions.** Define `%Backpex.Preferences.Effect{action: atom, key: String.t(), value: any()}`. Add new actions as new values or struct extensions. Typespec-checkable.
- **Option Y — invert ownership.** Adapters persist directly; return `:ok | {:defer, (Plug.Conn.t() -> Plug.Conn.t())} | {:error, _}`. Session adapter defers via a captured function; Ecto persists. Dispatcher applies the defer or falls back to `push_event`.

Recommendation: **Option Y** — removes the session-specific vocabulary from the abstraction, handles future transports naturally.

### D3 · `put_async/4` rename (resolves M2)

- **Option P — rename to `put/4`** (or `put_from/4`). Add `@deprecated` on `put_async/4` for a cycle. Breaking after the deprecation cycle.
- **Option Q — keep the name.** Document "async" means "browser-side, via keepalive fetch" in the moduledoc.

Recommendation: **Option P** for long-term API cleanliness, given the PR is already breaking.

---

## Copilot comment cross-check

| # | File | Verdict | Notes |
|---|------|---------|-------|
| 1 | `guides/live_resource/user-preferences.md:516-521` | **Agree, stronger** | See **B4**. The recipe isn't just docs-wrong; the whole `custom.*` JS write path is aspirational. |
| 2 | `lib/backpex/html/resource.ex:575-589` | Agree | See **m3**. Remove unused attr. |
| 3 | `lib/backpex/preferences.ex:157-172` | **Agree, architecturally deeper** | See **B1** + **D1**. `reduce_while` is necessary but insufficient. |
| 4 | `lib/backpex/preferences.ex:163-169` | Agree | See **m1**. Trivial fix; folds into B1 resolution. |
| 5 | `lib/backpex/html/layout.ex:504-510` | Agree | See **m2**. Use `assign_new/3`. |

---

## Suggested fix dispatch (for the agent team)

One agent per independent concern. Parallelizable except where noted.

| Bucket | Items | Dependency |
|--------|-------|------------|
| Batch semantics | B1, B8, m1 | **B8 depends on B1 fix** |
| Router | B2, M10 | independent |
| Dispatcher edges | B3, B9, M1, M2, M4, m4, m5, m6 | **M2 rename affects every doc** |
| Adapter protocol | M3 | blocks by D2 decision |
| Testing | B7, M5, M6, M11 | independent |
| JS + demo | B4, B5 | **B4 depends on D-pick (export vs rewrite recipe)** |
| Docs | B6, M8, M9, m11, m12 | independent |
| Small code hygiene | M7, m2, m3, m7, m8, m9, m10 | independent |

Each finding's `Verify` step is the acceptance criterion for that fix. A fix is not done until its verification passes.
