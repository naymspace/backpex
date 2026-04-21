# Suggested title

**Add user preferences system with pluggable storage adapters**

---

# Body

## Summary

Introduces a unified preference system that persists UI state (theme, sidebar, column visibility, ordering, filters, custom keys) through a pluggable adapter layer. Preferences are server-rendered from the adapter on every page load — no flicker on first paint, no round-trip before the UI reflects saved state.

Out of the box everything lives in the Phoenix session (zero config). Route any prefix to a per-user database in config:

```elixir
config :backpex, Backpex.Preferences,
  adapters: [
    {"global.*",   Backpex.Preferences.Adapters.Session, []},
    {"resource.*", MyApp.Preferences.EctoAdapter, repo: MyApp.Repo},
    {:default,     Backpex.Preferences.Adapters.Session, []}
  ],
  identity: {MyAppWeb.PreferencesIdentity, :resolve, []}
```

## Architecture

### Core modules

| Module                                | Responsibility                                                                                      |
|---------------------------------------|------------------------------------------------------------------------------------------------------|
| `Backpex.Preferences.Adapter`         | Behavior. `get/3`, `get_map/3`, `put/4`. `put/4` returns side effects, doesn't touch `Plug.Conn`.   |
| `Backpex.Preferences.Router`          | Longest-prefix match over configured routes. `:default` fallback.                                    |
| `Backpex.Preferences.Context`         | Read/write context (source, session, conn, assigns, memoized identity).                              |
| `Backpex.Preferences.Key`             | Parse/build keys. Supports `:` as a secondary separator so module-name dots stay as one segment.     |
| `Backpex.Preferences.Adapters.Session`| Default adapter; also the reference implementation for custom adapters.                              |

### Dispatcher API (`Backpex.Preferences`)

- `get/3` — read, fall back to `:default`. Accepts a `%Context{}` or a bare session map.
- `get_map/3` — read a prefix as a nested map.
- `put/4` — write from a socket or conn; falls back to `push_event/3` when the adapter can't write from a LiveView context.
- `put_batch/3` — cross-adapter batch writes, **all-or-nothing**. Threads accumulated session state between adapter calls so `put_session` effects over the same key compose correctly.

### Identity resolution

One MFA in config (`identity: {Mod, :fun, []}`); the dispatcher calls it once per context and memoizes on `ctx.identity`. Adapters that need a user id read `ctx.identity` rather than re-resolving per call.

### Opt-in persistence for index state

New `persist:` option on `use Backpex.LiveResource`:

```elixir
use Backpex.LiveResource,
  adapter_config: [...],
  persist: [:order, :filters, :columns]
```

- `:order` — reads `resource:<Mod>:order` on mount; writes on `handle_params` when order changes.
- `:filters` — reads `resource:<Mod>:filters` on mount; writes on `handle_params` when filters change.
- `:columns` — reads `resource:<Mod>:columns` on mount; writes on the `toggle_column` event.

Default is `[]`: the URL is the source of truth for order and filters, and column state lives in-memory.

### Built-in key reference

| Key                                        | Type    | Where it's read               | Where it's written                       | Opt-in?               |
|--------------------------------------------|---------|-------------------------------|------------------------------------------|-----------------------|
| `global.theme`                             | string  | `InitAssigns`                 | JS theme selector                        | always on             |
| `global.sidebar_open`                      | boolean | `InitAssigns`                 | JS sidebar toggle                        | always on             |
| `global.sidebar_section.<id>`              | boolean | `InitAssigns` (`get_map`)     | JS sidebar section toggle                | always on             |
| `resource:<Mod>:columns`                   | map     | Index view mount              | `toggle_column` event                    | `persist: [:columns]` |
| `resource:<Mod>:metrics_visible`           | boolean | Index view mount              | `toggle_metrics` event                   | always on             |
| `resource:<Mod>:order`                     | map     | Index view mount (fallback)   | `handle_params` (on change)              | `persist: [:order]`   |
| `resource:<Mod>:filters`                   | map     | Index view mount (fallback)   | `handle_params` (on change)              | `persist: [:filters]` |

### Key encoding

Keys whose segments contain dots (typically because a segment embeds a module name like `MyApp.MyLive`) use `:` as the separator: `resource:MyApp.MyLive:columns` parses into three clean segments. Keys without embedded module names use the usual dot form: `global.theme`.

## Breaking changes (v0.19 overhaul)

Spelled out in full in [guides/upgrading/v0.19.md](guides/upgrading/v0.19.md):

- `Backpex.ThemeSelectorPlug` removed — theme is populated by `Backpex.InitAssigns`.
- Root layout uses `@current_theme` instead of `@theme`.
- `theme_selector` component takes `current_theme`.
- `app_shell` component takes `sidebar_open`.
- `BackpexSidebar` hook replaces `BackpexSidebarSections`.

With no `:backpex, Backpex.Preferences` config, every key routes to the Session adapter — this matches the zero-config default and keeps behavior stable for apps that don't opt into a custom adapter.

## Migration — opting into a DB-backed adapter

1. Implement `Backpex.Preferences.Adapter` against your table (two complete recipes in the [guide](guides/live_resource/user-preferences.md)).
2. Add an identity resolver MFA.
3. Add one config block:
   ```elixir
   config :backpex, Backpex.Preferences,
     adapters: [
       {"resource.*", MyApp.Preferences.EctoAdapter, repo: MyApp.Repo},
       {:default, Backpex.Preferences.Adapters.Session, []}
     ],
     identity: {MyAppWeb.PreferencesIdentity, :resolve, []}
   ```
4. Opt in per resource:
   ```elixir
   persist: [:order, :filters, :columns]
   ```

## Documentation

- [guides/live_resource/user-preferences.md](guides/live_resource/user-preferences.md): architecture diagram, key reference table, two Ecto adapter recipes (generic k/v table + prefix→column mapping), identity resolver walkthrough, `persist:` migration example, troubleshooting.
- [guides/upgrading/v0.19.md](guides/upgrading/v0.19.md): "Preferences: adapter architecture" section.

## Testing

`MIX_ENV=test mix test`: **105 doctests + 203 tests, 0 failures**.
`mix lint`: credo clean, `mix format --check-formatted` clean, `mix compile --warnings-as-errors` clean.

### Test plan

Session-adapter preferences (default config):

- [ ] Toggle the sidebar open/closed → reload → state persists.
- [ ] Switch the theme via the theme selector → reload → `<html data-theme>` reflects the choice.
- [ ] Expand/collapse a sidebar section → reload → section state persists.
- [ ] Each write produces a `POST /backpex_preferences` returning `{ok: true}`.

Opt-in `persist:` on a demo LiveResource (e.g. `DemoWeb.PostLive` at `/admin/posts`):

- [ ] Add `persist: [:order, :filters, :columns]` to the resource.
- [ ] Sort by a column → reload at the base URL (no query params) → sort is restored.
- [ ] Apply a filter → reload at the base URL → filter is restored.
- [ ] Toggle column visibility → reload → hidden columns remain hidden.
- [ ] On a resource without `persist:`, the same actions reset on reload (proves the flag gates persistence).

Cross-adapter routing:

- [ ] Configure `resource.*` to an ETS-backed test adapter; re-run the opt-in checks; writes land in ETS and the session cookie stays empty for resource keys.

Error paths:

- [ ] Unauthenticated user hits a write routed to a DB adapter → response is `200 {ok: false, errors: [{:unidentified, ...}]}`, no exception.
- [ ] Adapter stubbed to raise on put → all-or-nothing: session unchanged, response is `{ok: false, errors: [...]}`.

## Stacked on

Stacked on top of [PR #1748](https://github.com/naymspace/backpex/pull/1748) (`feature/collapsible-sidebar`). Retargets to `develop` once that merges.
