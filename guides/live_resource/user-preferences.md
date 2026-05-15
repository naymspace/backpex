# User Preferences

Backpex persists UI state — theme, sidebar, per-resource column visibility,
metric toggles, and anything you want to add — through a pluggable adapter
layer. Out of the box everything lives in the Phoenix session (zero config
required). Configure a database adapter for one prefix and the rest stay in
the session; every setting is routed independently.

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
│                    Server-rendered HTML with correct state               │
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
│   Best-effort apply: {ok: true} or {ok: false, error: {key, reason}}     │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

**Key benefits:**

- **No flicker.** The server renders initial state from the adapter on every
  request, so the first paint is already correct.
- **Instant UI.** Writes are async (`keepalive: true`) — the browser never
  blocks on persistence.
- **Storage is your call.** Per-browser session is the default; swap any
  prefix onto a per-user database with a few lines of config.

## Contracts

Backpex dispatches every preference read and write through a
`%Backpex.Preferences.Context{}` carrying the current session **and** the
current `assigns` (controller `conn.assigns` on the write path,
`socket.assigns` on the LiveView read path). Adapters — and the identity
resolver they share — are expected to read from `ctx.assigns` first and fall
back to `ctx.session` only when the assigns view is empty.

For that guarantee to hold, the host app must satisfy a handful of
ordering and content contracts. None of these are enforced at compile time,
so it is worth spelling them out explicitly.

### Ordering: auth runs first

- **LiveView read path.** `Backpex.InitAssigns` must be attached **after**
  your app's authentication `on_mount` hook so that `socket.assigns` already
  holds `:current_user` / `:current_scope` by the time preferences are read.
  In a typical Phoenix 1.8 `live_session`:

  ```elixir
  live_session :authenticated,
    on_mount: [
      {MyAppWeb.UserAuth, :ensure_authenticated},
      Backpex.InitAssigns
    ] do
    # ... Backpex routes ...
  end
  ```

  If the order is reversed, `InitAssigns` will see an empty `socket.assigns`
  and your identity resolver will have to fall back to reading the raw
  session token — defeating the point of threading assigns through.

- **Controller write path.** The preferences controller is mounted behind
  the standard browser pipeline. As long as your auth plug runs before
  `Backpex.PreferencesController`, `conn.assigns` already contains the
  authenticated user by the time `Preferences.put/4` or
  `Preferences.put_batch/3` executes. This is true by construction of
  `Plug.Conn.assigns` but worth stating.

### The identity resolver receives a Context

Your resolver gets a `%Backpex.Preferences.Context{}`, not a raw session.
Read from `ctx.assigns` first — it is the post-auth, freshest view. Fall
back to `ctx.session` only for edge cases where assigns cannot carry the
answer (e.g. a non-LiveView write path that bypasses your auth `on_mount`
but still sits behind the router's session + auth plug pipeline):

```elixir
defmodule MyAppWeb.PreferencesIdentity do
  alias Backpex.Preferences.Context

  # Primary: whatever your auth layer put on assigns.
  def resolve(%Context{assigns: %{current_scope: %{user: %{id: id}}}}), do: id
  def resolve(%Context{assigns: %{current_user: %{id: id}}}), do: id

  # Fallback: a raw session token. Useful when you truly only have a
  # session on hand (background jobs, tests, hand-crafted calls).
  def resolve(%Context{session: %{"user_token" => token}}) when is_binary(token) do
    case MyApp.Accounts.get_user_by_session_token(token) do
      %{id: id} -> id
      _ -> :unidentified
    end
  end

  def resolve(_ctx), do: :unidentified
end
```

The resolver runs once per dispatcher call and its result is cached on the
context for the rest of that single dispatch (so one read never invokes it
twice). Keep it cheap all the same — every `Preferences.get/3` and
`Preferences.put/4` call triggers a fresh resolution.

### Session key must survive `renew_session`

Phoenix's `renew_session/1` helper (commonly called on login/logout to
rotate the session id) drops every session key unless explicitly preserved.
Backpex stores its session-backed preferences under
`Backpex.Preferences.session_key/0` (currently `"backpex_preferences"`) — if
you call `renew_session` in your auth flow, carry that key across:

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
user id, not the session. This note only matters for prefixes routed to
`Backpex.Preferences.Adapters.Session`.

## Built-in preference keys

Every key Backpex reads or writes is listed here. Third-party code should
prefix its own keys with `custom.` to avoid colliding with Backpex.

| Key                                        | Type     | Read at                                  | Written at                            | Opt-in?                 |
|--------------------------------------------|----------|------------------------------------------|---------------------------------------|-------------------------|
| `global.theme`                             | string   | `Backpex.InitAssigns`                    | JS theme selector                     | always on               |
| `global.sidebar_open`                      | boolean  | `Backpex.InitAssigns`                    | JS sidebar toggle                     | always on               |
| `global.sidebar_section.<id>`              | boolean  | `Backpex.InitAssigns` (via `get_map/3`)  | JS sidebar section toggle             | always on               |
| `resource:<Module>:columns`                | map      | Index view mount                         | `toggle_column` event                 | `persist: [:columns]`   |
| `resource:<Module>:metrics_visible`        | boolean  | Index view mount                         | `toggle_metrics` event                | always on               |
| `resource:<Module>:order`                  | map      | Index view mount (fallback)              | `handle_params` (on change)           | `persist: [:order]`     |
| `resource:<Module>:filters`                | map      | Index view mount (fallback)              | `handle_params` (on change)           | `persist: [:filters]`   |

Keys with embedded module names use `:` as a separator so module-name dots
(e.g. `MyApp.MyLive`) don't create extra path segments. See
`Backpex.Preferences.Key`.

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

## Storage adapters

An adapter owns the "where" of preference storage. Backpex ships one
(`Backpex.Preferences.Adapters.Session`) and lets you plug in others per
prefix. `Backpex.Preferences` routes each call through the adapter configured
for the key's prefix.

### Picking an adapter

| If you want…                                                    | Use…                                                |
|-----------------------------------------------------------------|-----------------------------------------------------|
| Zero config, per-browser state, small values (theme, sidebar)   | Session (default)                                   |
| Per-user, survives across devices, bulky values (columns, filters) | Ecto adapter (you write it — see recipes below)   |
| Pluggable per setting (e.g. theme in session, columns in DB)    | Mix both, route by prefix                           |

The Session adapter stores everything in a single Phoenix session key. If
your session is cookie-backed the whole tree must fit under ~4KB, so avoid
routing bulky per-resource state there.

### Routing by prefix

```elixir
# config/config.exs
config :backpex, Backpex.Preferences,
  adapters: [
    {"global.*",   Backpex.Preferences.Adapters.Session, []},
    {"resource.*", MyApp.Preferences.EctoAdapter, repo: MyApp.Repo},
    {:default,     Backpex.Preferences.Adapters.Session, []}
  ],
  identity: {MyAppWeb.PreferencesIdentity, :resolve, []}
```

Dispatch uses **longest-prefix match**, so specific patterns always beat
`:default` regardless of order. Patterns:

- `"global.*"` — any key whose first segment is `"global"`.
- `"global.theme"` — exact match, beats `"global.*"`.
- A 1-arity function `(String.t() -> boolean())` — escape hatch for
  cross-cutting carve-outs (see below).
- `:default` — fallback when nothing else matches.

With no `:adapters` config, the router falls back to a single `:default` →
Session route so existing apps need no changes.

#### Match functions — cross-cutting carve-outs

Trailing-wildcard patterns can only carve off a *prefix* of the key space.
When you need to route by a **suffix** (e.g. send every resource's column
visibility to the session while the rest of `resource.*` goes to a database),
use a 1-arity function as the pattern:

```elixir
config :backpex, Backpex.Preferences,
  adapters: [
    # Match funs are the most specific route type. Use them for cross-cutting
    # carve-outs (e.g., every resource's column visibility regardless of module).
    {&String.ends_with?(&1, ":columns"), Backpex.Preferences.Adapters.Session, []},
    {"resource.*", MyApp.Preferences.EctoAdapter, repo: MyApp.Repo},
    {:default, Backpex.Preferences.Adapters.Session, []}
  ]
```

Semantics:

- **Match functions are the most specific tier.** They always beat string
  patterns and `:default`, regardless of how specific those look. Rationale:
  the user wrote imperative matching code, so we assume they know what they
  are doing.
- **First-in-config-order wins among multiple matching functions.** This
  differs from the longest-prefix rule that applies to string patterns — make
  sure ordering is deliberate when you have more than one function route.
- **Match functions are excluded from `get_map/3` (subtree reads).** A
  function that picks off individual keys (every key ending in `:columns`)
  cannot cleanly own the subtree rooted at `resource.SomeLive`. Only string
  patterns and `:default` participate in subtree owner lookups. If you also
  need the matched keys reachable through a subtree read, pair the function
  route with a string pattern that owns the whole subtree.

### Identity resolver

Database adapters need a user id. Rather than each adapter implementing its
own lookup, configure **one** resolver and every adapter gets the result:

```elixir
# config/config.exs
config :backpex, Backpex.Preferences,
  identity: {MyAppWeb.PreferencesIdentity, :resolve, []}
```

```elixir
defmodule MyAppWeb.PreferencesIdentity do
  alias Backpex.Preferences.Context

  # Prefer assigns: Backpex passes the live socket's / conn's assigns in
  # `ctx.assigns`, so whatever your auth layer put there (current_scope,
  # current_user, ...) is already resolved by the time preferences are read.
  def resolve(%Context{assigns: %{current_scope: %{user: %{id: id}}}}), do: id
  def resolve(%Context{assigns: %{current_user: %{id: id}}}), do: id

  # Fall back to the raw session only when assigns can't answer (e.g. a
  # non-LiveView write path, a test that constructed a Context by hand).
  def resolve(%Context{session: %{"user_token" => token}}) when is_binary(token) do
    case MyApp.Accounts.get_user_by_session_token(token) do
      %{id: id} -> id
      _ -> :unidentified
    end
  end

  def resolve(_ctx), do: :unidentified
end
```

See the [Contracts](#contracts) section for why the assigns-first order
matters and what the host app must guarantee for it to hold.

The dispatcher calls the resolver once per read/write call — there is no
cross-call memoization, so the resolver runs every time. Keep it cheap
(assigns lookup, session read, or a fast cache hit). The resolved value is
stashed on `ctx.identity` so each adapter call during that single dispatch
reuses the same value. Return `:unidentified` (or raise) when no user is
logged in. Adapter reads are treated as "not found" and the caller falls
back to the `:default` option; writes return `{:error, :unidentified}` and
the controller responds `200 {ok: false, errors: [{…, :unidentified}]}`.

## Writing a custom adapter

Implement `Backpex.Preferences.Adapter`. Three callbacks:

- `get/3` — read one key. Return `{:ok, value}` or `{:ok, :not_found}`.
- `get_map/3` — read everything under a prefix as a nested map.
- `put/4` — persist one value; return a list of **side effects** for the
  caller to apply (`[:noop]` if you already persisted; `[{:put_session, k,
  map}]` when you need the caller to update the session).

The side-effect protocol is what keeps adapters pure. They don't touch
`Plug.Conn` — they describe what the caller should do. This is what lets
the controller compose cross-adapter batch writes and lets server-side code
dispatch the same adapters without an HTTP request.

Batch writes are **best-effort, first-error-wins**: on the first adapter
error the dispatcher halts, returns `{:error, {key, reason}}`, and the
controller responds `422 {ok: false, error: %{key: _, reason: _}}` without
applying any session-backed side effects collected earlier in the batch.
Adapters that persist eagerly (e.g. a DB-backed adapter that wrote via
`Repo.insert!`) may have already committed earlier writes — the adapter
behaviour has no rollback primitive, so callers should treat partial
success as possible.

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
    case :ets.lookup(@table, {identity(ctx), key}) do
      [{_, value}] -> {:ok, value}
      [] -> {:ok, :not_found}
    end
  end

  @impl true
  def get_map(ctx, prefix, _opts) do
    start()
    # Reconstruct a nested map from flat (identity, key) rows — see
    # lib/backpex/preferences/adapters/session.ex for the shape to return.
    {:ok, %{}}
  end

  @impl true
  def put(ctx, key, value, _opts) do
    start()
    :ets.insert(@table, {{identity(ctx), key}, value})
    {:ok, [:noop]}
  end

  defp identity(%{identity: nil}), do: :anonymous
  defp identity(%{identity: :unidentified}), do: :anonymous
  defp identity(%{identity: id}), do: id
end
```

Backpex itself uses exactly this pattern for its dispatcher tests — see
`test/support/in_memory_preferences_adapter.ex` for a fully-worked version.

## Ecto adapter recipes

Backpex ships the adapter behavior but not an Ecto adapter, because the
right table shape depends on how your app already organizes user data. Below
are two complete recipes — pick whichever matches your schema.

### Recipe A — generic key/value table

Good default when you don't already have a settings/profile table. Each row
is one preference.

```elixir
defmodule MyApp.Repo.Migrations.CreateBackpexUserPreferences do
  use Ecto.Migration

  def change do
    create table(:backpex_user_preferences) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :key,     :string, null: false
      add :value,   :map,    null: false, default: %{}
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:backpex_user_preferences, [:user_id, :key])
  end
end

defmodule MyApp.Preferences.UserPreference do
  use Ecto.Schema
  import Ecto.Changeset

  schema "backpex_user_preferences" do
    field :user_id, :integer
    field :key,     :string
    field :value,   :map, default: %{}
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(user_preference, attrs) do
    user_preference
    |> cast(attrs, [:user_id, :key, :value])
    |> validate_required([:user_id, :key, :value])
    |> unique_constraint([:user_id, :key])
  end
end

defmodule MyApp.Preferences.EctoAdapter do
  @behaviour Backpex.Preferences.Adapter

  import Ecto.Query
  alias MyApp.Preferences.UserPreference

  @impl true
  def get(%{identity: :unidentified}, _key, _opts), do: {:ok, :not_found}
  def get(%{identity: user_id}, key, opts) do
    repo = Keyword.fetch!(opts, :repo)

    case repo.one(from p in UserPreference, where: p.user_id == ^user_id and p.key == ^key, select: p.value) do
      nil -> {:ok, :not_found}
      %{"__raw__" => value} -> {:ok, value}
      value -> {:ok, value}
    end
  end

  @impl true
  def get_map(%{identity: :unidentified}, _prefix, _opts), do: {:ok, %{}}
  def get_map(%{identity: user_id}, prefix, opts) do
    repo = Keyword.fetch!(opts, :repo)
    like = prefix <> "%"

    rows =
      repo.all(
        from p in UserPreference,
          where: p.user_id == ^user_id and like(p.key, ^like),
          select: {p.key, p.value}
      )

    nested = reshape_to_nested(rows, prefix)
    {:ok, nested}
  end

  @impl true
  def put(%{identity: :unidentified}, _key, _value, _opts), do: {:error, :unidentified}
  def put(%{identity: user_id}, key, value, opts) do
    repo = Keyword.fetch!(opts, :repo)

    attrs = %{user_id: user_id, key: key, value: wrap_value(value)}

    %UserPreference{}
    |> UserPreference.changeset(attrs)
    |> repo.insert!(on_conflict: {:replace, [:value, :updated_at]}, conflict_target: [:user_id, :key])

    {:ok, [:noop]}
  end

  defp wrap_value(map) when is_map(map), do: map
  defp wrap_value(other), do: %{"__raw__" => other}

  defp reshape_to_nested(rows, prefix) do
    prefix_segments = Backpex.Preferences.Key.parse(prefix)

    Enum.reduce(rows, %{}, fn {key, value}, acc ->
      value = case value do
        %{"__raw__" => v} -> v
        v -> v
      end

      segments = Backpex.Preferences.Key.parse(key)
      case Enum.split(segments, length(prefix_segments)) do
        {^prefix_segments, []} -> acc
        {^prefix_segments, rest} -> put_path(acc, rest, value)
        _ -> acc
      end
    end)
  end

  defp put_path(map, [k], value), do: Map.put(map, k, value)

  defp put_path(map, [k | rest], value) do
    child = Map.get(map, k)
    child = if is_map(child), do: child, else: %{}
    Map.put(map, k, put_path(child, rest, value))
  end
end

# config/config.exs
config :backpex, Backpex.Preferences,
  adapters: [
    {"resource.*", MyApp.Preferences.EctoAdapter, repo: MyApp.Repo},
    {:default,     Backpex.Preferences.Adapters.Session, []}
  ]
```

### Recipe B — prefix → column mapping

Use when you already have a user settings table (one row per user) with
typed JSON columns. Lets each Backpex prefix write into a named column
rather than a generic rows table.

When you already have a typed settings table, adapt Recipe A by replacing
the k/v schema: route each prefix to its own column and dispatch reads and
writes based on the key's segments. See the
[ash_backpex](https://github.com/enoonan/ash_backpex) community example for
a working implementation.

## Opt-in persistence for ordering, filters, columns

By default `Backpex.LiveResource` keeps ordering and filters in the URL and
column visibility in-memory. Opt in per resource to persist any subset via
`Backpex.Preferences`:

```elixir
use Backpex.LiveResource,
  adapter_config: [...],
  persist: [:order, :filters, :columns]
```

What each flag does:

- **`:order`** — reads `resource:<Module>:order` at mount; uses it as the
  initial order when the URL has no `order_by` / `order_direction` params.
  Writes every time the order changes.
- **`:filters`** — reads `resource:<Module>:filters` at mount; uses it as
  the fallback filter set when the URL has no `filters` param. Writes every
  time filters change.
- **`:columns`** — reads `resource:<Module>:columns` at mount; writes on
  `toggle_column` events. Default without opt-in is to keep column state
  in-memory only.

All three keys route through whichever adapter you configured for
`"resource.*"` — typically the Session adapter by default, or a per-user DB
adapter once you wire one up.

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
# MyApp.OrderingSettings writes move into MyApp.Preferences.EctoAdapter once;
# every opt-in resource benefits.
```

## Custom preferences

The system is a flat key-value store with a namespace convention. Use
`custom.*` for your own keys — the router won't collide with anything Backpex
ships.

### Reading (server-side)

```elixir
def mount(_params, session, socket) do
  view_mode = Backpex.Preferences.get(session, "custom.dashboard.view_mode", default: "grid")
  panel_states = Backpex.Preferences.get_map(session, "custom.dashboard.panels")

  {:ok, assign(socket, view_mode: view_mode, panel_states: panel_states)}
end
```

### Writing from the browser

```javascript
import { BackpexPreferences } from 'backpex'

BackpexPreferences.set('custom.dashboard.view_mode', 'list')
```

### Writing from the server

From a LiveView `handle_event`, use `Backpex.Preferences.put/4`:

```elixir
def handle_event("toggle_view_mode", _params, socket) do
  new_mode = if socket.assigns.view_mode == "grid", do: "list", else: "grid"

  {:ok, socket} = Backpex.Preferences.put(socket, "custom.dashboard.view_mode", new_mode)

  {:noreply, assign(socket, :view_mode, new_mode)}
end
```

Under the hood `put/4` tries the configured adapter first. When the
adapter is session-backed (no HTTP request in a LiveView event), it falls
back to a `push_event/3` round-trip so the browser persists via the
preferences controller on its next paint. DB-backed adapters just write
directly and return.

### Validating custom keys

Preference keys are strings, and nothing stops a hand-written `"custm.foo"`
from compiling and silently returning the default. Backpex ships an
opt-in validator to catch typos mechanically.

**The `custom.*` convention.** Keep every app-owned key under the
`custom.*` prefix (`custom.dashboard.view_mode`, `custom.density.compact`,
…). The validator accepts `global.*`, `resource.*`, and `custom.*` out of
the box — anything else is flagged.

**Registering an extra prefix.** Rare, but occasionally an app has a
genuine reason to want its own top-level prefix (e.g. a distinct
`experimental.*` namespace during a rollout). Configure it:

```elixir
# config/config.exs
config :backpex, Backpex.Preferences.Key,
  extra_prefixes: ["experimental"]
```

Prefer `custom.<your-domain>.<key>` first — an extra prefix is extra
configuration every future contributor has to know about.

**Turning the validator on.** Default is off so production logs stay
quiet. Turn it on where typos are a problem:

```elixir
# config/dev.exs — warn about typos while developing
config :backpex, Backpex.Preferences, validate_keys: :log

# config/test.exs — fail the test suite if anything emits an unknown key
config :backpex, Backpex.Preferences, validate_keys: true
```

`:log` emits `Logger.warning/1` on each unknown key and still dispatches
the call (returns the default on reads). `true` raises `ArgumentError` on
the spot, surfacing typos as loud test failures. The validator runs on
`get/3`, `fetch/3`, `get_map/3`, and `put/4`. `put_batch/3` is intentionally
skipped — it is the cross-adapter dispatch used by
`Backpex.PreferencesController` and should not reject requests for an
unknown prefix at the library boundary.

`Backpex.Preferences.Keys` supplies helpers (`theme/0`, `sidebar_open/0`,
`columns/1`, …) that are self-checked at compile time to always emit
valid keys. Prefer those over inline strings whenever a built-in key
exists — and let the validator catch the remaining hand-written
`custom.*` strings.

## Gotchas

### Preserving preferences across session renewal

The Phoenix-generated `UserAuth.renew_session/2` pattern clears the session
on login/logout and re-puts an allowlist of keys. Unless you know the
specific session key Backpex uses, it will silently drop on renewal — users
lose their theme, sidebar state, and persisted filters/order/columns every
time they sign in or out.

Use `Backpex.Preferences.Session.preserve/1` and `restore/2` to include
Backpex preferences in the renewal without hardcoding the session key:

```elixir
def renew_session(conn, _user) do
  backpex_prefs = Backpex.Preferences.Session.preserve(conn)

  conn
  |> configure_session(renew: true)
  |> clear_session()
  |> then(&Backpex.Preferences.Session.restore(&1, backpex_prefs))
end
```

Both calls are no-ops when no preferences are stored, so they are safe to
add unconditionally.

### Default vs. explicit empty

When deciding whether to apply a default, use `Backpex.Preferences.fetch/3`
and pattern-match on `:error` vs `{:ok, value}`. Don't treat a resolved
`%{}` or `[]` as "never set" — a user who explicitly cleared their filters
(or their columns, or any other map/list preference) stored that empty
value deliberately. Overwriting it with a default on the next mount means
every page load fights the user's choice.

```elixir
# Wrong — treats "user cleared filters" the same as "no preference".
filters = Backpex.Preferences.get(session, key, default: %{})
if filters == %{}, do: apply_defaults(), else: use(filters)

# Right — distinguishes the two.
case Backpex.Preferences.fetch(session, key) do
  {:ok, filters} -> use(filters)         # includes an explicit %{}
  :error         -> apply_defaults()     # user has never set this
  {:error, _}    -> apply_defaults()     # adapter failure, already logged
end
```

`Backpex.LiveResource`'s own `persist: [:filters]` wiring follows this
rule; apply the same pattern in any custom persistence logic you build on
top of `Backpex.Preferences`.
## Cross-tab sync (PubSub)

Preference writes are fire-and-forget: the browser POSTs, the adapter
persists, and the rest of the app learns about the change on the next fresh
mount. That is fine for a single tab. It is not fine for two tabs of the
same admin — toggling theme in one leaves the other on the stale value
until the user reloads it.

Backpex can broadcast every successful write on a Phoenix PubSub so other
LiveViews (other tabs, other connections for the same user) can react in
real time. The feature is **opt-in** and costs nothing when unconfigured.

### Enable it

```elixir
# config/config.exs
config :backpex, Backpex.Preferences,
  adapters: [...],
  identity: {MyAppWeb.PreferencesIdentity, :resolve, []},
  pubsub: [server: MyApp.PubSub, topic_prefix: "backpex_preferences"]
```

- `:server` — the name of your Phoenix PubSub process. Usually the one
  your endpoint already starts.
- `:topic_prefix` — optional. Defaults to `"backpex_preferences"`. Change
  it only if it collides with something your app already broadcasts on.

When `:pubsub` is absent, writes do not broadcast at all. No PubSub
lookup, no try/rescue — zero cost.

### Message shape

After every successful `put/4` **and** every successful entry in
`put_batch/3`, Backpex broadcasts on `"<topic_prefix>:<identity>"`:

```elixir
{:backpex_preference_changed,
 %{key: "global.theme", value: "dark", source: :controller}}
```

- `:source` is `:controller` for HTTP-controller writes (the hot path —
  the JS hook POSTing to the preferences endpoint) and `:server` for
  server-side `Preferences.put/4` calls from a LiveView that bypassed
  the browser.
- Failed writes do not broadcast. Neither does the `:requires_http`
  fallback path: the socket hands the write to the browser and the
  browser's POST will produce the broadcast with `:source == :controller`.
- Broadcast failures (misconfigured server name, etc.) are logged and
  swallowed — a bad broadcast NEVER breaks a preference write.

### Subscribe from a LiveView

```elixir
def mount(_params, _session, socket) do
  if connected?(socket) do
    Backpex.Preferences.subscribe(socket.assigns.current_user.id)
  end

  {:ok, socket}
end

def handle_info({:backpex_preference_changed, %{key: "global.theme", value: theme}}, socket) do
  # Re-render with the new theme. Your handler decides how much to reconcile;
  # a simple `assign(:current_theme, theme)` is often enough.
  {:noreply, assign(socket, :current_theme, theme)}
end

def handle_info({:backpex_preference_changed, _other}, socket) do
  # Ignore keys this view does not care about.
  {:noreply, socket}
end
```

`Backpex.Preferences.subscribe/1` takes an identity — whatever your
identity resolver returns. Use the same value here that the resolver would
resolve to for the current user; otherwise your subscription will miss
broadcasts targeted at a different topic. `unsubscribe/1` mirrors it.

### Why per-identity topics

Broadcasting globally would fan every user's write out to every other
user's session — a privacy leak dressed up as a feature. Backpex keys the
topic off the resolved identity so each user's tabs are the only ones
listening. Writes made with no resolved identity (`:unidentified` from the
resolver, or no resolver configured) land on `"<topic_prefix>:anonymous"`
so they stay debuggable but don't cross-pollinate. Consumer code that
subscribes for real users should ignore the anonymous topic.

### Gotcha: `:unidentified` writes

If your identity resolver returns `:unidentified` for a write (anonymous
visitor, background job, test), the broadcast lands on the anonymous topic.
This is intentional — it keeps the write path simple and the broadcasts
inspectable during development — but it means a `subscribe(user_id)`
call will not receive `:unidentified` writes for that user. Make sure your
resolver consistently returns the same identity on both the read and write
paths.

## Testing Backpex LiveResources

When a resource has [filter presets](../filter/filter-presets.md) (a
`:default` on a filter config) and the user has no persisted filter state
yet, the Index view issues a `push_navigate` on first mount to apply those
defaults. Under `Phoenix.LiveViewTest.live/2` that surfaces as an
`{:error, {:live_redirect, _}}` tuple that your test has to match on and
re-mount — every integrator hits this footgun the first time they write an
Index-mount test.

`Backpex.Test` ships helpers that absorb that boilerplate. Import it in
your ExUnit cases (no extra dependency; the module is part of the Backpex
package):

```elixir
import Backpex.Test
```

### `live_resource_index/3`

Mounts a LiveResource Index view and transparently follows the default-filter
redirect if one is issued:

```elixir
test "index renders with the preset filters applied", %{conn: conn} do
  {:ok, _view, html} = live_resource_index(conn, MyAppWeb.PostLive)
  assert html =~ "Published"
end
```

Pass the **top-level** LiveResource module (`MyAppWeb.PostLive`), not the
generated `*.Index` sub-module. The macro uses the conn's router (which
Phoenix populates after the first dispatch in a `ConnCase` test) to derive
the Index URL.

Options:

- `:url` — override the mount URL entirely. Use this when the resource is
  mounted under multiple paths, or when you want to pass exactly the query
  string you care about.
- `:query` — a map or keyword list merged into the derived URL's query
  string. Ignored when `:url` is set.

A redirect to a **different** path bubbles up as the original `{:error, ...}`
tuple rather than being silently followed — one hop only.

### `put_preference/3`

Seeds a preference into the conn's session before mount, without going
through the HTTP preferences controller. Handy for pinning
persisted-state-on-mount branches:

```elixir
test "persisted empty filters suppress the default-filter redirect", %{conn: conn} do
  conn =
    conn
    |> put_preference(Backpex.Preferences.Keys.filters(MyAppWeb.PostLive), %{})

  {:ok, _view, html} = live_resource_index(conn, MyAppWeb.PostLive)

  # No redirect — the explicit empty filter state beat the `:default`.
  assert html =~ "Draft"
  assert html =~ "Published"
end
```

`put_preference/3` dispatches through the configured adapter the same way
any production write does — so tests that swap in a DB-backed adapter also
see their seeds persisted there, not only in the session.

## Writing a JS hook that persists preferences

### Why sessionStorage mirroring exists

LiveView freezes the Phoenix session at websocket-connect time. The
`BackpexPreferences.set/2` HTTP POST writes immediately to the cookie, but
an in-flight LiveView socket holds the older session snapshot until the
next fresh connect. When a user clicks an internal link that does a
`live_redirect`, LiveView re-mounts the target view **on the same socket**
— so `on_mount` callbacks (including `Backpex.InitAssigns`) read the stale
snapshot and the server re-renders UI chrome from the pre-write value.
The user sees a momentary reversion of their own toggle.

To survive that re-mount the JS hook needs a client-authoritative value
that bypasses the server entirely. `sessionStorage` is the natural fit:
same tab, cleared on tab close, no cookie-size pressure. `BackpexPreferences`
provides `get(key, fallback)` and `set(key, value, { mirror: 'session' })`
so every hook gets the same, namespaced (`backpex.prefs.*`) behavior
without reinventing load/save helpers.

### When to use `mirror: 'session'`

Use it when **all** of the following are true:

- The preference controls UI chrome re-rendered by the LiveView on every
  mount (sidebar, density, nav variant, table zoom, …).
- The server reads this preference from the session at mount time (so the
  stale snapshot will bite you on `live_redirect`).
- The client-side value can diverge from the server's view between a
  write and the next fresh websocket handshake.

### When NOT to use it

Skip the mirror (just call `BackpexPreferences.set(key, value)`) when:

- The server is always authoritative on every render — e.g. a DB-backed
  preference read fresh from Ecto in `mount/3`. There's no stale snapshot
  to override.
- The visible UI state lives outside the LiveView-rendered tree. The
  built-in theme selector is an example: `data-theme` on `<html>` is set
  once by JS and never re-rendered by the server, so a stale session read
  only mislabels the (hidden-by-default) selector radio and isn't worth
  the overhead.
- You need cross-tab consistency within the browser — `sessionStorage` is
  per-tab; a mirror there will diverge between two tabs of the same admin.

### Example: a compact-density toggle

```javascript
// assets/js/hooks/compact_density_toggle.js
import { BackpexPreferences } from 'backpex'

export default {
  mounted () {
    // Seed from the mirror first (live_redirect-safe), falling back to
    // the server-rendered data attribute on fresh connects.
    const compact = BackpexPreferences.get(
      'custom.density.compact',
      this.el.dataset.compact === 'true'
    )
    this.applyDensity(compact)

    this.el.addEventListener('click', () => {
      const next = !this.el.classList.contains('density-compact')
      this.applyDensity(next)
      // Writes sessionStorage first (instant, survives live_redirect),
      // then POSTs to the preferences endpoint for the next fresh connect.
      BackpexPreferences.set('custom.density.compact', next, { mirror: 'session' })
    })
  },

  applyDensity (compact) {
    this.el.classList.toggle('density-compact', compact)
    this.el.setAttribute('aria-pressed', String(compact))
  }
}
```

`get/2` uses the runtime type of the fallback to deserialize: a boolean
fallback returns `true`/`false`; a number returns a parsed number; a string
passes through; anything else (map, array) round-trips through JSON. Pick
a fallback whose type matches what you `set/3`-ed originally and the
round-trip stays transparent.

## Troubleshooting

**"My preferences vanish after a few writes."** The default cookie-backed
session has a hard ~4KB limit; once the tree overflows, the session silently
truncates. Route bulky prefixes (columns, filters) onto a database adapter.

**"Changes aren't saving for some users."** The configured adapter likely
returned `{:error, :unidentified}` — your identity resolver couldn't find a
user (e.g. auth plug hasn't run yet). Check `Plug.Conn.get_session(conn,
:user_id)` / `socket.assigns.current_user` at the moment the write is made.

**"I want to inspect what's stored for a user."** Session adapter: read
`Plug.Conn.get_session(conn, "backpex_preferences")` directly. DB adapter:
query your table (`backpex_user_preferences` or whatever you named it).

**"How do I reset a user's preferences?"** Drop their rows (DB adapter) or
`Plug.Conn.delete_session(conn, "backpex_preferences")` (session). No
Backpex-specific API exists — treat the store like the data store it is.
