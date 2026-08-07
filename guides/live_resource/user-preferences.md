# User Preferences

Backpex persists UI state — theme, sidebar, per-resource column visibility,
metric toggles, and anything you want to add — through a pluggable adapter
layer. Out of the box everything lives in the Phoenix session (zero config
required). To route one prefix to a database and keep the rest in the session,
configure that route **and** an explicit Session `:default` route; once an
`:adapters` list exists, Backpex does not add an implicit fallback. Every
setting is routed independently.

## How It Works

```
                                 INITIAL PAGE LOAD
┌──────────────────────────────────────────────────────────────────────────┐
│                                                                          │
│   Browser   ──cookie──▶   Backpex.InitAssigns                            │
│                                │                                         │
│                                ▼                                         │
│                       Backpex.Preferences.get/3                          │
│                                │                                         │
│                                ▼                                         │
│                    Router (longest-prefix match)                         │
│                        │              │                                  │
│                    global.*       resource.*                             │
│                        │              │                                  │
│                        ▼              ▼                                  │
│                 Session adapter   Ecto adapter (user-provided)           │
│                        │              │                                  │
│                        └──────┬───────┘                                  │
│                               ▼                                          │
│                    Server-rendered HTML with resolved state              │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘

                             USER CHANGES STATE
┌──────────────────────────────────────────────────────────────────────────┐
│                                                                          │
│   JS toggle or LiveView push_event                                       │
│            │                                                             │
│            ▼                                                             │
│   BackpexPreferences.set(key, value)                                     │
│            │                                                             │
│            ▼                                                             │
│   POST /backpex_preferences  (async, keepalive)                          │
│            │                                                             │
│            ▼                                                             │
│   Backpex.PreferencesController → Preferences.put_batch/2                │
│            │                                                             │
│            ▼                                                             │
│   Router → adapter(s) → side effects                                     │
│            │                                                             │
│            ▼                                                             │
│   Best-effort apply: {"ok":true} or {"ok":false,"error":{...}}        │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

**Key benefits:**

- **Server-rendered state.** The server renders stored state from the adapter
  on every request. A bounded pending cookie covers most reloads that race an
  in-flight write; see its size and scope limitations below.
- **Instant UI.** Writes are async (`keepalive: true`) — the browser never
  blocks on persistence.
- **Storage is your call.** Per-browser session is the default; swap any
  prefix onto a per-user database with a few lines of config.

### What Backpex stores in the browser

| Store | Name | Lifetime | Holds |
|---|---|---|---|
| Your app's session cookie | e.g. `_my_app_key` | your session config | Where the Session adapter persists preferences. |
| `sessionStorage` | `backpex.prefs.<route token>.<key>` | the tab | Per-tab mirror of preferences written since the websocket connected. Opt-in per key and isolated by its adapter namespace. |
| Cookie | `backpex_prefs` | `max-age` 300, normally deleted within one round-trip | Preference writes the server has not acknowledged yet, each stamped with its adapter namespace token. |

`backpex_prefs` is written by JavaScript — synchronously, which is the whole
point — so it is **not** `HttpOnly`. Attributes: `path=/`, `SameSite=Lax`,
`max-age=300`, plus `Secure` over HTTPS. The value is a versioned envelope,
`{"version": 1, "values": {key: {"token": "...", "value": value}}}`, holding
the writes whose POST has not come back yet. Each entry is deleted as soon as
its POST responds, so the cookie is absent most of the time. Backpex reads it on
the disconnected mount only — it is an input to a *render*, never to an adapter
write. Unlike the `sessionStorage` mirror it is shared across tabs of the same
browser. See [Why the client sometimes overrides the server](#why-the-client-sometimes-overrides-the-server).

The encoded cookie has a 3072-byte budget. If several pending writes exceed it,
Backpex evicts the oldest entries until it fits. If one entry cannot fit, it is
not written to the cookie. No pending cookie is written when the page lacks a
usable signed preferences manifest. Persistence still proceeds in both
cases, but a document reload inside the POST round trip may initially render the
previous stored value.

If your app shows a cookie-consent banner, `backpex_prefs` is designed as a
strictly functional cookie: it carries keyed namespace tokens rather than raw
user or tenant ids and exists only to render the state the user just requested. Confirm the
classification required by your own jurisdiction and consent policy.

### Scoping browser-carried values per adapter

The cookie can outlive the person who wrote it: a preference toggled a moment
before "Log out" leaves a POST in flight whose promise dies with the page, so
nothing ever retires the entry and it sits there for up to five minutes. If the
next user logs in inside that window, an unscoped cookie would be overlaid onto
*their* first paint and replayed into *their* store.

One application can route `global.*` into the Phoenix session and
`resource.*` into a tenant-scoped database. A single fingerprint of the whole
application scope is therefore too broad for the Session adapter and too narrow
for the database adapter. Backpex instead signs one **client namespace token per
adapter route**. Each token is a keyed digest over the endpoint's
`secret_key_base`, the adapter module, the namespace reported by that adapter,
and the Phoenix session's CSRF token.

The built-in adapters report the namespace they actually use:

- `Backpex.Preferences.Adapters.Session` reports the Phoenix preferences session
  key and deliberately ignores the application scope. Its token stays stable
  when the current tenant changes, so theme and sidebar state survive tenant
  navigation.
- `Backpex.Preferences.Adapters.Ecto` reports its repo, schema, and exactly the
  values named by `scope_fields`. Its token changes only when a field that can
  select another database row changes.

Custom adapters may implement the optional
`c:Backpex.Preferences.Adapter.client_namespace/2` callback and return any stable
term that uniquely identifies their storage namespace. Adapters that omit the
callback conservatively use the complete resolved application scope plus their
route options.

`Backpex.InitAssigns` renders the signed route list into
`data-preferences-manifest` (pass
`preferences_manifest={@preferences_manifest}` to `app_shell`). The browser
routes each key through that manifest and discards only entries whose own token
no longer matches; compatible siblings remain. The preferences endpoint path is
transport metadata, not part of the namespace, so changing a dynamic tenant URL
does not invalidate a compatible Session-backed mirror.

The disconnected mount repeats token validation and does not trust the browser
to discard an outlived or planted cookie. The digest is keyed, so neither the
manifest nor browser storage exposes raw session, user, or tenant identifiers.

When tokens cannot be signed — no `secret_key_base`, a layout that does not pass
the manifest, or the very first request of a brand-new session, whose CSRF token
`Plug.CSRFProtection` only writes back at the end of the response — Backpex
behaves as though the browser overlay did not exist: a first paint that may be
one write stale, never a value attributed to the wrong namespace.

Because the cookie is browser-written and unsigned, anything any script on the
origin can plant reaches a render. `Backpex.Preferences.Context.put_client/2`
therefore filters both client carriers — the cookie and the connect params —
before they become an overlay (the namespace token is an *additional* gate, not
a replacement: it says which store owns a value, not that the value is sane):

- keys that fail `Backpex.Preferences.Key.validate/1` are dropped;
- values that fail `Backpex.Preferences.Keys.valid_value?/2` are dropped.

Neither is an authorization gate — a client can already POST any value it likes
to the preferences endpoint. They exist because a render must not raise on
browser input: `inert={not @sidebar_open}` raises on a string, so without the
value gate a single planted cookie would 500 every admin page until it expired.
A rejected entry simply falls back to the stored value.

Backpex can only shape-check the keys it owns. If you read your **own** keys out
of the overlay, treat their values as untrusted input and render defensively —
see `Backpex.Preferences.Keys.valid_value?/2`.

## Contracts

Backpex dispatches every preference read and write through a
`%Backpex.Preferences.Context{}`, but the available session and assigns depend
on how that context was built:

| Call path | `ctx.session` | `ctx.assigns` | Client overlay |
|---|---|---|---|
| `Backpex.Preferences.LiveView.mount_context(socket, session)` | current mount session | `socket.assigns` | cookie or connect params |
| `Backpex.Preferences.Context.from_conn(conn)` / `Preferences.put(conn, ...)` | current conn session | `conn.assigns` | none |
| bare session passed to `get/3` or `get_map/3` | supplied session | `%{}` | none |
| `Preferences.put(socket, ...)` | `%{}` | `socket.assigns` | none |
| explicitly constructed `%Context{}` | whatever the caller supplied | whatever the caller supplied | whatever the caller supplied |

Adapters — and the scope resolver they share — should prefer
`ctx.assigns`, then fall back to `ctx.session` only on call paths that actually
carry a session. In particular, a server-originated LiveView write must resolve
scope from `socket.assigns`; `Preferences.put(socket, ...)` does not have the
mount session.

For that guarantee to hold, the host app must satisfy a handful of
ordering and content contracts. None of these are enforced at compile time,
so it is worth spelling them out explicitly.

### Ordering: authentication and application scope run first

- **LiveView read path.** `Backpex.InitAssigns` must be attached **after**
  every hook that builds the application scope so that `socket.assigns`
  already holds the user, tenant, workspace, or other namespace fields by the
  time preferences are read.
  In a typical Phoenix 1.8 `live_session`:

  ```elixir
  live_session :authenticated,
    on_mount: [
      {MyAppWeb.UserAuth, :ensure_authenticated},
      {MyAppWeb.TenantAuth, :assign_tenant},
      Backpex.InitAssigns
    ] do
    # ... Backpex routes ...
  end
  ```

  If the order is reversed, `InitAssigns` will see an empty `socket.assigns`
  and the resolver cannot construct the complete scope. Do not silently fall
  back to a user-only scope when a tenant field is required: that would merge
  preferences across tenants.

- **Controller write path.** Mount the preferences controller behind a
  pipeline that constructs the same application scope. For a tenant-scoped
  store, put the endpoint below the tenant segment and authorize the tenant
  before the controller:

  ```elixir
  scope "/tenants/:tenant", MyAppWeb do
    pipe_through [:browser, :require_authenticated_user, :assign_tenant]

    backpex_routes()
  end
  ```

  The generated route contains a dynamic segment, so pass its concrete path
  to the layout:

  ```heex
  <Backpex.HTML.Layout.app_shell
    socket={@socket}
    preferences_manifest={@preferences_manifest}
    preferences_path={~p"/tenants/#{@current_scope.tenant.id}/backpex_preferences"}
  >
    ...
  </Backpex.HTML.Layout.app_shell>
  ```

### The scope resolver receives a Context

Your resolver gets a `%Backpex.Preferences.Context{}`, not a raw session.
Read from `ctx.assigns` — it is the post-auth, post-tenant view. A raw session
usually cannot reconstruct a complete tenant scope. Return `:unscoped` rather
than returning a partial map that could join namespaces accidentally:

```elixir
defmodule MyAppWeb.PreferencesScope do
  alias Backpex.Preferences.Context

  def resolve(%Context{
        assigns: %{
          current_scope: %{user: %{id: user_id}, tenant: %{id: tenant_id}}
        }
      }) do
    %{user_id: user_id, tenant_id: tenant_id}
  end

  def resolve(_ctx), do: :unscoped
end
```

The resolver runs once for each unresolved context. Reusing the resolved
context — as `Backpex.InitAssigns` does for all reads during one mount — reuses
the same scope. Calls that start from a bare session, conn, or socket build a
fresh context and resolve again. Keep the resolver cheap.

### Session key must survive `renew_session`

The `renew_session` helper that `phx.gen.auth` generates (commonly called
on login/logout to rotate the session id) clears the session and re-puts
only an allowlist of keys. Every key outside that allowlist is dropped.
Backpex stores its session-backed preferences under
`Backpex.Preferences.session_key/0` (currently `"backpex_preferences"`) — if
you call `renew_session` in your auth flow, carry that key across, or users
lose their theme, sidebar state, and persisted filters/order/columns every
time they sign in or out:

```elixir
def renew_session(conn) do
  prefs = Plug.Conn.get_session(conn, Backpex.Preferences.session_key())

  conn
  |> configure_session(renew: true)
  |> clear_session()
  |> then(fn c ->
    if prefs, do: put_session(c, Backpex.Preferences.session_key(), prefs), else: c
  end)
end
```

DB-backed adapters are unaffected by `renew_session` — they key off the
resolved scope map, not the session. This note only matters for prefixes routed to
`Backpex.Preferences.Adapters.Session`.

## Built-in preference keys

Every key Backpex reads or writes is listed here. Third-party code should
prefix its own keys with `custom.` to avoid colliding with Backpex.

| Key                                        | Type     | Read at                                  | Written at                            | Opt-in?                 |
|--------------------------------------------|----------|------------------------------------------|---------------------------------------|-------------------------|
| `global.theme`                             | string   | `Backpex.InitAssigns`                    | JS theme selector                     | always on               |
| `global.sidebar_open`                      | boolean  | `Backpex.InitAssigns`                    | JS desktop sidebar toggle             | always on               |
| `global.sidebar_section.<id>`              | boolean  | `Backpex.InitAssigns` (via `get_map/3`)  | JS sidebar section toggle             | always on               |
| `resource:<Module>:columns`                | map      | Index view mount                         | `toggle_column` event                 | `persist: [:columns]`   |
| `resource:<Module>:metrics_visible`        | boolean  | Index view mount                         | `toggle_metrics` event                | `persist: [:metrics]`   |
| `resource:<Module>:order`                  | map      | Index view mount (fallback)              | `handle_params` (on change)           | `persist: [:order]`     |
| `resource:<Module>:filters`                | map      | Index view mount (fallback)              | `handle_params` (on change)           | `persist: [:filters]`   |

Keys with embedded module names use `:` as a separator so module-name dots
(e.g. `MyApp.MyLive`) don't create extra path segments. See
`Backpex.Preferences.Key`.

`global.sidebar_open` stores only the desktop (`lg` and wider) state. The mobile
drawer always starts closed and mobile open/close actions are not persisted.

Sidebar section ids become the final segment of
`global.sidebar_section.<id>`. Use unique ids matching `[A-Za-z0-9_-]+`.
Dots and colons alter preference-key parsing, and quotes or backslashes are
unsafe in the browser hook's attribute selector.

Sections without a descendant marked with `data-sidebar-item` stay hidden
through CSS, so they cannot flash before the LiveView hooks mount.
`sidebar_item/1` adds the marker automatically; custom leaf markup must add it
explicitly. Nested sections become visible as soon as any descendant contains a
marked item.

## Reading preferences in your layout

`Backpex.InitAssigns` already populates the assigns that the built-in layout
needs:

```elixir
@current_theme           # "light", "dark", ...
@sidebar_open            # true | false
@sidebar_section_states  # %{"blog" => true, "settings" => false}
```

```heex
<Backpex.HTML.Layout.app_shell
  socket={@socket}
  fluid={@fluid?}
  live_resource={@live_resource}
  sidebar_open={@sidebar_open}
  preferences_manifest={@preferences_manifest}
>
  <:topbar>
    <Backpex.HTML.Layout.theme_selector
      current_theme={@current_theme}
      themes={[{"Light", "light"}, {"Dark", "dark"}]}
    />
  </:topbar>
  <:sidebar>
    <Backpex.HTML.Layout.sidebar_section
      id="blog"
      sidebar_section_states={@sidebar_section_states}
    >
      <:label>Blog</:label>
    </Backpex.HTML.Layout.sidebar_section>
  </:sidebar>
</Backpex.HTML.Layout.app_shell>
```

### Custom layouts must render `preferences_root`

Every preference write is sent by the `BackpexPreferences` JS hook, which reads
the endpoint to POST to from a single element on the page:

```heex
<div id="backpex-preferences" phx-hook="BackpexPreferencesHook" data-preferences-path=... />
```

`Backpex.HTML.Layout.app_shell/1` renders that element for you, so a layout
built on `app_shell` needs nothing extra. A layout that does **not** use
`app_shell` must render it itself, once per page:

```heex
<Backpex.HTML.Layout.preferences_root
  socket={@socket}
  preferences_manifest={@preferences_manifest}
/>
```

Without it, every write — theme, sidebar, sidebar sections, and the
`persist:` keys — is dropped. The failure is quiet: the UI updates
optimistically, so it looks like it worked until the next reload reverts it,
and the only signal is a console warning.

## Storage adapters

An adapter owns the "where" of preference storage. Backpex ships Session and
Ecto adapters (the Ecto adapter uses your application's schema and table) and
lets you plug in others per prefix. `Backpex.Preferences` routes each call
through the adapter configured for the key's prefix.

### Picking an adapter

| If you want…                                                    | Use…                                                |
|-----------------------------------------------------------------|-----------------------------------------------------|
| Zero config, per-browser state, small values (theme, sidebar)   | Session (default)                                   |
| Per-user, survives across devices, bulky values (columns, filters) | `Backpex.Preferences.Adapters.Ecto`                 |
| Pluggable per setting (e.g. theme in session, columns in DB)    | Mix both, route by prefix                           |

The Session adapter stores everything in a single Phoenix session key. If
your session is cookie-backed, the **entire encoded session cookie** — Backpex
preferences plus your application's other session data, signing/encryption
overhead, and cookie attributes — must fit the browser/Plug limit of 4096
bytes.

The adapter enforces that budget rather than letting the store raise. On every
write it estimates the size of the resulting cookie — the whole session, not
just Backpex's subtree, since the budget is shared with your app's own session
data — and:

- logs a warning once the estimate passes 75% of the budget, and
- refuses the write with `{:error, :too_large}` once it would exceed it,
  leaving the previously stored value untouched.

A refused write surfaces to the browser as `422 {ok: false, error: %{reason:
"too_large"}}`, and the JS hook stops carrying it. The alternative would be a
`Plug.Conn.CookieOverflowError` — an HTTP 500 on this and every later request,
with no way for the user to reach a page to undo it.

The warning is the signal to route heavy prefixes (per-resource column
visibility, saved filters, etc.) to a database-backed adapter before writes
start being refused. If your session is **not** cookie-backed (ETS, Redis, a
database), the 4KB cap does not apply — lift it:

```elixir
config :backpex, Backpex.Preferences,
  adapters: [
    {:default, Backpex.Preferences.Adapters.Session, max_bytes: :infinity}
  ]
```

The estimate is approximate by design: it is a budget check, not an exact
reproduction of `Plug.Session`'s encoding. It errs toward over-estimating, so
it refuses slightly before the true ceiling rather than slightly after.

### Routing by prefix

```elixir
# config/config.exs
config :backpex, Backpex.Preferences,
  adapters: [
    {"global.*",   Backpex.Preferences.Adapters.Session, []},
    {"resource.*", Backpex.Preferences.Adapters.Ecto,
     repo: MyApp.Repo,
     schema: MyApp.Preferences.Preference,
     scope_fields: [:user_id, :tenant_id]},
    {:default,     Backpex.Preferences.Adapters.Session, []}
  ],
  scope: {MyAppWeb.PreferencesScope, :resolve, []}
```

Dispatch uses **longest-prefix match**, so specific patterns always beat
broader ones and `:default` regardless of the order they appear in config.
Patterns:

- `"global.*"` — a wildcard: every key under the `global` prefix.
- `"global.theme"` — an exact key; beats `"global.*"`.
- `:default` — fallback when nothing else matches.

With no `:adapters` config, the router falls back to a single `:default` →
Session route so existing apps need no changes.

Once you configure `:adapters`, that zero-config fallback is disabled. Every
key must match a configured exact/wildcard route or an explicit `:default`.
Otherwise `Backpex.Preferences.Router` raises when it first resolves the
unmatched key. Include
`{:default, Backpex.Preferences.Adapters.Session, []}` when unspecified keys
should remain session-backed.

#### Routing a single resource

Patterns are split into segments by the same rule as keys, so a wildcard can
address one resource by name. Per-resource keys embed the module as a single
`:`-separated segment — `Backpex.Preferences.Keys.columns(MyApp.PostLive)` is
`"resource:MyApp.PostLive:columns"` — and a pattern written the same way carves
that resource out of the broader `"resource.*"` route:

```elixir
config :backpex, Backpex.Preferences,
  adapters: [
    # PostLive carries far more column state than the session cookie should hold.
    {"resource:MyApp.PostLive:*", Backpex.Preferences.Adapters.Ecto,
     repo: MyApp.Repo,
     schema: MyApp.Preferences.Preference,
     scope_fields: [:user_id, :tenant_id]},
    {"resource.*", Backpex.Preferences.Adapters.Session, []},
    {:default, Backpex.Preferences.Adapters.Session, []}
  ]
```

The narrower route owns every `MyApp.PostLive` key; every other resource still
goes to the session. Order does not matter — specificity decides.

`"*"` is only valid as the **final** segment. A bare `"*"`, or a pattern like
`"resource.*.columns"`, can never match a key, so Backpex raises when the
adapter config is first normalized (normally on the first preference route
resolution) rather than letting the keys you meant to route quietly land
somewhere else. Use `:default` to match every key.

There is no suffix or predicate matching: adapters own exact keys or prefixes
of the key space. A subtree read (`get_map/3`) reads every intersecting route
and applies the same specificity rules, so an exact key or nested wildcard can
live in another adapter without becoming invisible to its parent subtree.

### Scope resolver

Database adapters need a namespace. Configure **one** resolver that returns a
non-empty atom-keyed map and every adapter receives it:

```elixir
# config/config.exs
config :backpex, Backpex.Preferences,
  scope: {MyAppWeb.PreferencesScope, :resolve, []}
```

```elixir
defmodule MyAppWeb.PreferencesScope do
  alias Backpex.Preferences.Context

  def resolve(%Context{
        assigns: %{
          current_scope: %{user: %{id: user_id}, tenant: %{id: tenant_id}}
        }
      }) do
    %{user_id: user_id, tenant_id: tenant_id}
  end

  def resolve(_ctx), do: :unscoped
end
```

See the [Contracts](#contracts) section for why the assigns-first order
matters and what the host app must guarantee for it to hold.

The dispatcher resolves each context once. Reusing a context with a populated
`scope` reuses the same map; entry points that receive a bare session, conn, or
socket build a fresh context and resolve again. Keep it cheap (assigns lookup,
session read, or a fast cache hit). Return `:unscoped` (or raise) when the complete scope
cannot be resolved. Adapter reads are treated as "not found" and the caller falls
back to the `:default` option; writes return `{:error, :unscoped}` and
the controller responds with a singular error object:
`200 {"ok": false, "error": {"key": "...", "reason": "unscoped"}}`
for a single write. In a batch, `:unscoped` is an ordinary first error and
returns the same body with status `422`.

## Writing a custom adapter

Implement `Backpex.Preferences.Adapter`. Three callbacks are required:

- `get/3` — read one key. Return `{:ok, value}` or `{:ok, :not_found}`.
- `get_map/3` — read everything under a prefix as a nested map.
- `put/4` — persist one value. Return `{:ok, :persisted}` when you stored it
  yourself (the usual case for a DB adapter), or `{:ok, {:put_session, key,
  map}}` to ask the caller to write `map` into the Phoenix session.

One callback is optional but recommended when the adapter does not use the
complete application scope:

- `client_namespace/2` — return `{:ok, stable_term}` describing exactly the
  namespace in which this adapter stores the current route's values. Backpex
  signs the term; it is never sent to the browser in the clear. Return
  `{:error, :unscoped}` when no safe namespace is available. If the callback is
  omitted, Backpex uses the complete resolved scope and the route options.

For example, an adapter keyed only by account should project away an unrelated
workspace switch:

```elixir
@impl true
def client_namespace(%Context{scope: %{account_id: account_id}}, _opts) do
  {:ok, {:account, account_id}}
end

def client_namespace(_ctx, _opts), do: {:error, :unscoped}
```

The term must change whenever the adapter could read a different value for the
same preference key, and remain stable when only transport details (such as a
dynamic endpoint path) change.

The side-effect protocol keeps adapters independent of `Plug.Conn`. A Session
adapter describes the session effect for the controller to apply; a database
adapter may perform its own storage write and return `{:ok, :persisted}`. This
lets the controller compose cross-adapter batch writes and lets server-side
code dispatch the same adapters without an HTTP request.

`{:put_session, _, _}` is only honorable on a `%Plug.Conn{}` —
`Plug.Session` is HTTP-only. An adapter that stores in the session must
return `{:error, :requires_http}` when called outside a controller (the
Session adapter does exactly this), so the dispatcher can round-trip the
write through the browser instead.

Batch writes are **best-effort, first-error-wins**: on the first adapter
error the dispatcher halts, returns `{:error, {key, reason}}`, and the
controller responds `422 {"ok": false, "error": {"key": "...", "reason":
"..."}}` without
applying any session-backed side effects collected earlier in the batch.
Adapters that persist eagerly (e.g. a DB-backed adapter that wrote via
`Repo.insert!`) may have already committed earlier writes — the adapter
behaviour has no rollback primitive, so callers should treat partial
success as possible.

### HTTP endpoint contract

`backpex_routes/0` mounts `POST /backpex_preferences` (under the surrounding
scope). `BackpexPreferences.set(...)` is the normal client and sends JSON with the
Phoenix CSRF header. Custom clients may send either supported payload shape:

```json
{"key": "custom.dashboard.view_mode", "value": "list"}
```

```json
{"preferences": [
  {"key": "global.theme", "value": "dark"},
  {"key": "global.sidebar_open", "value": false}
]}
```

The response contract is:

- `200 {"ok": true}` when all retained entries were accepted.
- `200 {"ok": false, "error": {"key": "...", "reason": "unscoped"}}`
  when a single write targets an adapter that cannot resolve its complete scope.
- `422 {"ok": false, "error": {"key": "...", "reason": "..."}}` for the
  first adapter error in a batch or any other write error.
- `400 {"ok": false, "error": "missing key/value"}` when the outer payload
  matches neither supported shape.

The batch parser silently discards members that are not objects containing a
binary `key` and a `value` field. An empty batch, or a batch where every member
is discarded, therefore returns `200 {"ok": true}` and performs no writes.

The dispatcher validates value shapes for keys Backpex owns, regardless of
whether the write came from the controller, a LiveView, or host application
code. A wrong-typed built-in value returns `:invalid_value` before any adapter
sees it. Unknown and `custom.*` keys remain adapter-owned and may carry any
value their adapter accepts; this shape check is not an authorization boundary.
Adapter reads are necessarily defensive too, because rows may predate the
validation or be written outside Backpex.

### Respond only once the value is readable

The browser retires its client overlay for a key as soon as the write's HTTP
response arrives, because a completed response means *the server has seen this
write* (see [Why the client sometimes overrides the
server](#why-the-client-sometimes-overrides-the-server)). An adapter that
persists **asynchronously** — a queued or fire-and-forget write, a database with
read-replica lag — breaks that rule: the overlay retires while the next read
still returns the old value, and the flicker the subsystem exists to remove
comes back. `put/4` must not return until the value is readable by a subsequent
`get/3`.

### In-memory test adapter

Useful when exercising preferences in integration tests without spinning up
a database:

```elixir
defmodule MyApp.Test.InMemoryPreferencesAdapter do
  @behaviour Backpex.Preferences.Adapter

  @table :my_app_test_prefs

  def start do
    case :ets.whereis(@table) do
      :undefined -> :ets.new(@table, [:named_table, :public, :set])
      _ref -> :ok
    end
  end

  def reset, do: (start(); :ets.delete_all_objects(@table); :ok)

  @impl true
  def get(ctx, key, _opts) do
    start()
    case :ets.lookup(@table, {scope(ctx), key}) do
      [{_, value}] -> {:ok, value}
      [] -> {:ok, :not_found}
    end
  end

  @impl true
  def get_map(ctx, prefix, _opts) do
    start()
    # Reconstruct a nested map from flat (scope, key) rows — see
    # lib/backpex/preferences/adapters/session.ex for the shape to return.
    {:ok, %{}}
  end

  @impl true
  def put(ctx, key, value, _opts) do
    start()
    :ets.insert(@table, {{scope(ctx), key}, value})
    {:ok, :persisted}
  end

  defp scope(%{scope: nil}), do: :unscoped
  defp scope(%{scope: scope}), do: scope
end
```

Backpex itself uses exactly this pattern for its dispatcher tests — see
`test/support/in_memory_preferences_adapter.ex` for a fully-worked version.

## Database-backed preferences

`Backpex.Preferences.Adapters.Ecto` stores one row per preference key. Reach
for it when you outgrow the Session adapter's ~4KB cookie budget, or when
preferences should follow a user across devices and browsers.

You supply the table; Backpex supplies the adapter. There is no adapter
module to write.

### Setup

```elixir
defmodule MyApp.Repo.Migrations.CreateBackpexPreferences do
  use Ecto.Migration

  def change do
    create table(:backpex_preferences) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :tenant_id, references(:tenants, on_delete: :delete_all), null: false
      add :key,     :string, null: false
      add :value,   :map,    null: false, default: %{}
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:backpex_preferences, [:user_id, :tenant_id, :key])
  end
end

defmodule MyApp.Preferences.Preference do
  use Ecto.Schema

  schema "backpex_preferences" do
    field :user_id, :integer
    field :tenant_id, :integer
    field :key,     :string
    field :value,   :map, default: %{}
    timestamps(type: :utc_datetime_usec)
  end
end
```

```elixir
# config/config.exs
config :backpex, Backpex.Preferences,
  adapters: [
    {:default, Backpex.Preferences.Adapters.Ecto,
     repo: MyApp.Repo,
     schema: MyApp.Preferences.Preference,
     scope_fields: [:user_id, :tenant_id],
     storage_key_prefix: "backpex."}
  ],
  scope: {MyAppWeb.PreferencesScope, :resolve, []}
```

The unique index is required and must contain `scope_fields ++ [:key]` in the
same order because writes use that list as their conflict target. Every scope
field must exist on the schema, and its type must match the corresponding value
returned by the scope resolver. The `:key` and `:value` field names are fixed.

`storage_key_prefix` is optional and defaults to `""`. When configured, the Ecto
adapter prepends it only in the database and removes it again on reads, so callers
continue using Backpex's logical keys. The value is used exactly as configured;
include the separator you want, for example `"backpex."` stores
`global.theme` as `backpex.global.theme`. Changing the prefix selects a new
storage namespace; existing rows under another prefix are not read or migrated.

> #### Match your app's primary key convention {: .warning}
>
> The schema above uses Ecto's default `:id` primary key. If your app sets
> `migration_primary_key: [type: :binary_id]` on the repo — or generates
> schemas from a base module that does — the migration creates a `uuid` `id`
> column with no database default, while a bare `use Ecto.Schema` still expects
> the database to fill it. Inserts then fail at runtime with `null value in
> column "id" violates not-null constraint`. Declare the primary key the way
> the rest of your schemas do:
>
> ```elixir
> @primary_key {:id, :binary_id, autogenerate: true}
> ```

The example routes every key through Ecto so theme, sidebar, filters, order and
columns are all tenant-scoped. Route selected prefixes to the Session adapter
only when those settings should deliberately be session-scoped instead.

### How values are stored

Preference values are frequently scalars — `metrics_visible` and every
`global.sidebar_section.<id>` are booleans, `global.theme` is a string — and a
`:map` column cannot hold those. Every value is therefore wrapped in a
`%{"value" => term}` envelope on write and unwrapped on read:

```
key                                             | value
------------------------------------------------+----------------------------------
backpex.global.sidebar_section.blog             | {"value": true}
backpex.resource:MyApp.PostLive:order           | {"value": {"by": "id", ...}}
```

The `backpex.` prefix in this example comes from `storage_key_prefix`; without
that option the logical keys are stored unchanged. Worth knowing when reading
the table by hand or asserting on rows in a test.

### Design variant — prefix → column mapping

Use when you already have a user settings table (one row per user) with typed
JSON columns, and want each Backpex prefix to write into a named column rather
than a generic rows table. That needs a custom adapter (see
[Writing a custom adapter](#writing-a-custom-adapter)); dispatch reads and
writes on the key's segments and build `get_map/3`'s return value with
`Backpex.Preferences.Adapter.nest/2`. The
[ash_backpex](https://github.com/enoonan/ash_backpex) community project is a
worked example.

## Opt-in persistence for ordering, filters, columns, metrics

By default `Backpex.LiveResource` keeps ordering and filters in the URL and
column and metric visibility in-memory. Opt in per resource to persist any
subset via `Backpex.Preferences`:

```elixir
use Backpex.LiveResource,
  adapter_config: [...],
  persist: [:order, :filters, :columns, :metrics]
```

What each flag does:

- **`:order`** — reads `resource:<Module>:order` at mount; uses it as the
  initial order when the URL has no `order_by` / `order_direction` params.
  Writes every time the user changes the order. A stored order takes
  precedence over `init_order` on later mounts, so nothing is written until
  the user actually picks one: passively viewing an index leaves the resource
  free to keep deciding its own default (see below).
- **`:filters`** — reads `resource:<Module>:filters` at mount; uses it as
  the fallback filter set when the URL has no `filters` param. Writes every
  time filters change.
- **`:columns`** — reads `resource:<Module>:columns` at mount; writes on
  `toggle_column` events. Default without opt-in is to keep column state
  in-memory only.
- **`:metrics`** — reads `resource:<Module>:metrics_visible` at mount;
  writes on `toggle_metrics` events. Default without opt-in is to show
  metrics on every mount and keep the toggle in-memory only.

All four keys route through whichever adapter you configured for
`"resource.*"` — typically the Session adapter by default, or a per-user DB
adapter once you wire one up.

### `:order` and `init_order`

A stored order overrides `init_order` from the next mount on. That is the
point of the option — but it means an order that gets stored is an order the
resource can no longer choose for that user. So a preference is written only
when the user picks an order (a column-header click, or `order_by` /
`order_direction` in the URL), never on a plain index view.

That keeps the two composable: `init_order` decides the default for as long as
the user has expressed no preference, including a `fun/1` that recomputes it
per render, and a user who has picked an order keeps it. Were the default
written on first view instead, it would freeze per user at whatever it
resolved to the first time they happened to open the page — and a later change
to the resource's default would never reach them.

### Replacing a hand-rolled persistence layer

If your app already persists ordering, filters, or column state through a
custom `init_order` callback backed by a DB table, the `persist:` option
replaces that scaffolding:

```elixir
# Hand-rolled
use Backpex.LiveResource, adapter_config: [...]

def init_order(assigns), do: MyApp.OrderingSettings.fetch(assigns.current_user, __MODULE__)

def handle_event(...) do
  # ... hand-rolled write to MyApp.OrderingSettings ...
end
```

```elixir
# With persist:
use Backpex.LiveResource,
  adapter_config: [...],
  persist: [:order]
# MyApp.OrderingSettings writes move into the configured preference adapter;
# every opt-in resource benefits.
```

## Custom preferences

The system is a flat key-value store with a namespace convention. Use
`custom.*` for your own keys — the router won't collide with anything Backpex
ships.

### Reading (server-side)

```elixir
def mount(_params, session, socket) do
  ctx = Backpex.Preferences.LiveView.mount_context(socket, session)

  view_mode = Backpex.Preferences.get(ctx, "custom.dashboard.view_mode", default: "grid")
  panel_states = Backpex.Preferences.get_map(ctx, "custom.dashboard.panels")

  {:ok, assign(socket, view_mode: view_mode, panel_states: panel_states)}
end
```

Use `mount_context/2` during `mount/3`, after your authentication on-mount
hook. It preserves `socket.assigns` for scope resolution and includes the
validated pending-cookie/connect-param overlay. Passing the bare `session`
map is supported, but it has no assigns and cannot see pending or per-tab
mirrored values.

### Writing from the browser

```javascript
import { BackpexPreferences } from 'backpex'

BackpexPreferences.set(
  'custom.dashboard.view_mode',
  'list',
  { mirror: 'session' }
)
```

### Writing from the server

From a LiveView `handle_event`, use `Backpex.Preferences.put/4`:

```elixir
def handle_event("toggle_view_mode", _params, socket) do
  new_mode = if socket.assigns.view_mode == "grid", do: "list", else: "grid"

  {:ok, socket} =
    Backpex.Preferences.put(
      socket,
      "custom.dashboard.view_mode",
      new_mode,
      mirror: :session
    )

  {:noreply, assign(socket, :view_mode, new_mode)}
end
```

Under the hood `put/4` tries the configured adapter first. When the
adapter is session-backed (no HTTP request in a LiveView event), it falls
back to a `push_event/3` round-trip so the browser persists via the
preferences controller on its next paint. DB-backed adapters just write
directly and return. `mirror: :session` matters on the Session fallback because
this preference is read at mount and must survive a same-socket live
navigation; it is ignored when the configured adapter persists server-side.

### Namespace and subtree limitations

Browser overlays accept only the top-level prefixes recognized by
`Backpex.Preferences.Key.validate/1`: `global`, `resource`, and `custom`. There
is no API for registering another top-level prefix. Put application-owned keys
under `custom.*` if they must participate in the pending cookie or LiveView
connect-param overlay.

`get_map/3` overlays client values by looking for dot-form descendants of
`prefix` (`prefix <> "."`). Use dot-separated `custom.*` keys for application
subtrees such as `custom.dashboard.panels.left`. A colon-form subtree such as
`resource:MyApp.PostLive:*` can still be read from adapters, but pending client
entries are not reconstructed into `get_map/3`; read those keys individually
with `get/3` when client-overlay precedence is required.

## Gotchas

### Default vs. explicit empty

Don't treat a resolved `%{}` or `[]` as "never set" — a user who explicitly
cleared their filters (or their columns, or any other map/list preference)
stored that empty value deliberately. Overwriting it with a default on the
next mount means every page load fights the user's choice.

Read with `Backpex.Preferences.get/3` and **no** `:default`. A missing value
then comes back as `nil`, so `is_nil/1` separates the two cases:

```elixir
# Wrong — treats "user cleared filters" the same as "no preference".
filters = Backpex.Preferences.get(session, key, default: %{})
if filters == %{}, do: apply_defaults(), else: use(filters)

# Right — distinguishes the two.
case Backpex.Preferences.get(session, key) do
  nil     -> apply_defaults()   # user has never set this
  filters -> use(filters)       # includes an explicit %{}
end
```

This is exactly what `Backpex.LiveResource`'s own `persist: [:filters]`
wiring does: it reads the persisted filters with a bare `get/3` and skips
the default-filter redirect whenever the result is not `nil`. Apply the same
pattern in any custom persistence logic you build on top of
`Backpex.Preferences`.

The default Session adapter reserves `nil` for “not found”: storing `nil` and
then reading it is indistinguishable from a missing key, even if you pass a
sentinel default. Store a tagged value such as `%{"value" => nil}` instead. A
custom adapter may preserve `nil` by returning `{:ok, nil}`; only with such an
adapter can `default: :__unset__` distinguish missing from stored `nil`.

## Testing Backpex LiveResources

When a resource has [filter presets](../filter/filter-presets.md) (a
`:default` on a filter config) and the user has no persisted filter state
yet, the Index view issues a `push_navigate` on first mount to apply those
defaults. Under `Phoenix.LiveViewTest.live/2` that surfaces as an
`{:error, {:live_redirect, _}}` tuple that your test has to match on and
re-mount — every integrator hits this footgun the first time they write an
Index-mount test.

Don't re-mount by hand. `Phoenix.LiveViewTest.follow_redirect/2` exists for
exactly this: pass it the `{:error, {:live_redirect, _}}` tuple and it mounts
the target for you, returning the usual `{:ok, view, html}`.

```elixir
test "index renders with the preset filters applied", %{conn: conn} do
  result = live(conn, ~p"/admin/posts")

  assert {:error, {:live_redirect, %{to: to}}} = result
  assert to =~ "filters[published][]=published"

  {:ok, _view, html} = follow_redirect(result, conn)
  assert html =~ "Published"
end
```

`follow_redirect/2` recycles the conn, carries the LiveView connect params
across the hop and re-signs the flash cookie, so the second mount sees the
session the first one did. When you don't need to assert on the target,
`conn |> live(~p"/admin/posts") |> follow_redirect(conn)` is the whole dance.

To seed a preference so that the mount reads it as if the user had set it
earlier — pinning a persisted-state branch such as "user explicitly cleared
all filters" — write it onto the conn with `Backpex.Preferences.put/3` before
mounting. It dispatches through the configured adapter just like a production
write, so an adapter backed by your database sees the seed too:

```elixir
alias Backpex.Preferences
alias Backpex.Preferences.Keys

test "persisted empty filters suppress the default-filter redirect", %{conn: conn} do
  {:ok, conn} = Preferences.put(conn, Keys.filters(MyAppWeb.PostLive), %{})

  # No redirect — the explicit empty filter state beat the `:default`.
  {:ok, _view, html} = live(conn, ~p"/admin/posts")

  assert html =~ "Draft"
  assert html =~ "Published"
end
```

## Writing a JS hook that persists preferences

### Why the client sometimes overrides the server

**The precedence rule, stated once: the client overrides the server exactly
when it holds a write the server has not acknowledged.** A write is
acknowledged once its POST to the preferences endpoint has come back with an
HTTP response — any response. `200 {"ok": true}`, the single-write
`200 {"ok": false, "error": {"key": "...", "reason": "unscoped"}}`
an anonymous visitor gets, and a `422` all count: the server has seen the write
and decided on it, so replaying it is pointless and keeping a client overlay
would pin the value forever. Until then, the browser is the only party that
knows what the user picked, and it has to carry that knowledge to the server
itself.

It does so over **two carriers**, because a page is rendered over two different
transports and each transport can only see one of them:

**The `backpex_prefs` cookie → the document GET (the disconnected "dead"
render).** `document.cookie` is written synchronously inside the click handler,
so the value rides the very next request the browser makes — including a reload
fired milliseconds later, long before the keepalive POST's `Set-Cookie` has
updated the session. Without it, the GET carries a session cookie that is up to
one POST round-trip stale, the first paint shows the pre-toggle state, and
LiveView patches it away a frame later: the flash. `Backpex.Preferences.LiveView`
decodes the cookie on the disconnected mount and folds it into the same client
overlay the connect params feed. Every key gets this automatically — mirrored or
not — which is why filters, order and column visibility also survive a fast
reload, not just the sidebar. A pending write only ever applies to the scope
that made it: see [Scoping browser-carried values per adapter](#scoping-browser-carried-values-per-adapter).

**The `sessionStorage` mirror → the websocket join.** LiveView freezes the
Phoenix session at websocket-connect time. When a user clicks an internal link
that does a `live_redirect`, LiveView re-mounts the target view **on the same
socket** — so `on_mount` callbacks (including `Backpex.InitAssigns`) read that
frozen snapshot and re-render UI chrome from the pre-write value. No HTTP
request happens there, so the cookie plays no part: the mirror is the only
carrier that exists on that path. `sessionStorage` is the natural fit — same
tab, cleared on tab close, no cookie-size pressure — and `BackpexPreferences`
provides `get(key, fallback)` and `set(key, value, { mirror: 'session' })` so
every hook gets the same namespaced (`backpex.prefs.*`) behavior without
reinventing load/save helpers. The mirror reaches the server in the **LiveView
connect params**, which is why `backpexParams` must be wired into your
`LiveSocket` (see the [installation guide](../get_started/installation.md)):
LiveView re-evaluates those params on every join, so `mount/3` sees the tab's
post-connect writes *before* it renders.

Both carriers feed the same server-side client overlay
(`Backpex.Preferences.Context`), so the dead render and the connected render
derive their state from the same values and agree by construction.

On the **first** join of a page load the browser reconciles the two. Every
mirrored key the server has *acknowledged* is dropped: the document GET just
re-read the storage backend, so for those keys its render is authoritative, and
a mirror left over from an earlier page load (or made stale by another tab
writing the shared session cookie) must not override it. Every key the server
has *not* acknowledged is kept and sent — the dead render already honored those
out of `backpex_prefs`, and withholding them would make the connected render
contradict the paint the user is looking at.

### When to use `mirror: 'session'`

`mirror` governs the **long-lived per-tab mirror** only. The short-lived pending
cookie is attempted for every key regardless, so the mirror choice is primarily
about whether the value must survive a `live_redirect`. The pending cookie is a
best-effort fast-reload carrier: it is capped at 3072 encoded bytes, evicts old
entries, skips a single oversized entry, and is disabled without a signed
preferences manifest.

Use it when **all** of the following are true:

- The preference controls state the LiveView re-renders on every mount —
  UI chrome (sidebar, density, nav variant, table zoom, …), the theme
  selector's checked radio, or server-rendered content such as column and
  metric visibility.
- The server reads this preference from the session at mount time (so the
  frozen snapshot will bite you on `live_redirect`).
- The client-side value can diverge from the server's view between a
  write and the next fresh websocket handshake.

### When NOT to use it

Skip the mirror (just call `BackpexPreferences.set(key, value)`) when:

- The value round-trips through something the server sees on every render
  anyway and is not also used as a persisted mount fallback. Transient filters
  and order with the default `persist: []` live entirely in the URL and do not
  need preference writes at all.
- The server is always authoritative on every render — e.g. a DB-backed
  preference read fresh from Ecto in `mount/3`. There's no frozen snapshot
  to override.
- You need cross-tab consistency within the browser — `sessionStorage` is
  per-tab; a mirror there will diverge between two tabs of the same admin.
  (`backpex_prefs` *is* shared across tabs, but it only ever holds a write for
  as long as its POST is in flight, so it cannot pin a divergence.)

When `persist: [:filters]` or `persist: [:order]` is enabled, Backpex does use
`mirror: :session` for the preference write. The URL remains authoritative when
it contains the relevant params, while the mirrored preference supplies the
mount fallback when it does not. Custom code should follow the same rule when a
URL-backed value is also persisted as a future default.

An unmirrored key still attempts to use the pending cookie for a fast reload.
What it always gives up is the `live_redirect` guarantee; if the pending cookie
cannot carry the entry, the first paint of a racing reload may also be stale.

### Server-originated writes: `Preferences.put/4`

The mirror also covers preferences the **server** writes, such as column and
metric visibility. These are server-rendered content (a hidden column is not in
the DOM at all), so a client hook cannot re-apply them the way the sidebar hooks
re-apply CSS state — the server has to know before it renders.

Write them from a LiveView with `Backpex.Preferences.put/4`:

```elixir
{:ok, socket} = Backpex.Preferences.put(socket, key, value, mirror: :session)
```

The **adapter** decides how that write lands, which is why this is the entry
point to reach for:

- An adapter that can persist server-side takes the write in place. The browser
  is never involved, the next mount reads the value back fresh, and `:mirror`
  is moot — there is no round-trip to mirror.
- The Session adapter cannot write outside an HTTP request cycle, so it refuses
  with `{:error, :requires_http}` and the dispatcher falls back to a
  `push_event` that the `BackpexPreferences` hook POSTs back. That round-trip is
  what `:mirror` governs:

  1. `mirror: :session` tells the hook to mirror the value into sessionStorage
     in addition to the POST.
  2. Every subsequent join sends the mirrored values in the connect params.
  3. `Backpex.Preferences.LiveView.mount_context/2` folds them into the
     `Context`, where `get/3` and `get_map/3` prefer them over the stored
     value — so the first render already reflects the toggle.

`Backpex.Preferences.LiveView.push_write/4` emits that `push_event` directly and
skips the adapter entirely. It is the transport primitive the fallback is built
on; prefer `put/4` unless you specifically need the browser round-trip, so that
a host routing your key to a server-side adapter does not pay for one it does
not need.

### Example: a compact-density toggle

```javascript
// assets/js/hooks/compact_density_toggle.js
import { BackpexPreferences } from 'backpex'

const KEY = 'custom.density.compact'

export default {
  mounted () {
    // Seed from the mirror first (live_redirect-safe), falling back to
    // the server-rendered data attribute on fresh connects.
    this.serverCompact = this.el.dataset.compact === 'true'
    this.compact = BackpexPreferences.get(KEY, this.serverCompact)
    this.applyDensity(this.compact)

    this.el.addEventListener('click', () => {
      this.compact = !this.el.classList.contains('density-compact')
      this.applyDensity(this.compact)
      // Marks the write pending in `backpex_prefs` (so a reload right now still
      // paints it), mirrors it to sessionStorage (so it survives live_redirect),
      // then POSTs to the preferences endpoint.
      BackpexPreferences.set(KEY, this.compact, { mirror: 'session' })
    })
  },

  updated () {
    const serverCompact = this.el.dataset.compact === 'true'
    if (serverCompact === this.serverCompact) return
    this.serverCompact = serverCompact

    // The attribute *changed*, so the server has new information — adopt it,
    // unless this tab holds a write the server has not acknowledged yet, in
    // which case the render we are looking at predates the user's click.
    if (!BackpexPreferences.isPending(KEY)) this.compact = serverCompact
    this.applyDensity(this.compact)
  },

  applyDensity (compact) {
    this.el.classList.toggle('density-compact', compact)
    this.el.setAttribute('aria-pressed', String(compact))
  }
}
```

Two API notes for hook authors:

- `get/2` uses the runtime type of the fallback to deserialize: a boolean
  fallback returns `true`/`false`; a number returns a parsed number; a string
  passes through; anything else (map, array) round-trips through JSON. Pick
  a fallback whose type matches what you `set/3`-ed originally and the
  round-trip stays transparent.
- `isPending(key)` is the gate any hook must check before adopting a
  server-rendered attribute. Re-asserting a cached client value on every
  `updated()` leaves the server no path to ever correct the hook; adopting the
  attribute unconditionally undoes a click the server has not seen yet. Adopt it
  when it *changed* and the key is not pending — that is the precedence rule,
  applied in the DOM. The built-in `BackpexSidebar` and `BackpexSidebarSections`
  hooks do exactly this.

## Troubleshooting

**"My preferences vanish after a few writes."** A cookie-backed session has a
hard size limit (commonly about 4KB for the complete encoded session, not just
Backpex's tree). Plug does not silently truncate an oversized session; the
response write may fail with `Plug.Conn.CookieOverflowError`. The
Session adapter warns once its own tree passes 3072 bytes, but other session
data and encoding overhead can make failure happen earlier. Route bulky
prefixes (columns, filters) onto a database adapter.

**"Changes aren't saving for some scopes."** The configured adapter likely
returned `{:error, :unscoped}` because the resolver could not build the full
scope, or `{:error, {:invalid_scope, fields}}` because a configured field was
missing. Check `conn.assigns` / `socket.assigns` after the authentication and
tenant hooks have run.

**"I want to inspect what's stored for a scope."** Session adapter: read
`Plug.Conn.get_session(conn, "backpex_preferences")` directly. DB adapter:
query your table (`backpex_user_preferences` or whatever you named it).

**"How do I reset a scope's preferences?"** Drop its rows (DB adapter) or
`Plug.Conn.delete_session(conn, "backpex_preferences")` (session). No
Backpex-specific API exists — treat the store like the data store it is.
