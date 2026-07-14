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

### What Backpex stores in the browser

| Store | Name | Lifetime | Holds |
|---|---|---|---|
| Your app's session cookie | e.g. `_my_app_key` | your session config | Where the Session adapter persists preferences. |
| `sessionStorage` | `backpex.prefs.*` | the tab | Per-tab mirror of preferences written since the websocket connected. Opt-in per key. |
| Cookie | `backpex_prefs` | `max-age` 300, normally deleted within one round-trip | Preference writes the server has not acknowledged yet, stamped with the identity that made them. |

`backpex_prefs` is written by JavaScript — synchronously, which is the whole
point — so it is **not** `HttpOnly`. Attributes: `path=/`, `SameSite=Lax`,
`max-age=300`, plus `Secure` over HTTPS. The value is an envelope, `{"id":
"<identity fingerprint>", "values": {key: value}}`, holding the writes whose POST
has not come back yet; each entry is deleted as soon as its POST responds, so the
cookie is absent most of the time. Backpex reads it on the disconnected mount
only — it is an input to a *render*, never to an adapter write. Unlike the
`sessionStorage` mirror it is shared across tabs of the same browser. See [Why
the client sometimes overrides the
server](#why-the-client-sometimes-overrides-the-server).

If your app shows a cookie-consent banner, classify `backpex_prefs` as
**strictly necessary**: it carries no identifier, is not readable by anyone but
the same origin, and exists only so the page the user just asked for renders in
the state they just asked for.

### Scoping the pending cookie to a user

The cookie can outlive the person who wrote it: a preference toggled a moment
before "Log out" leaves a POST in flight whose promise dies with the page, so
nothing ever retires the entry and it sits there for up to five minutes. If the
next user logs in inside that window, an unscoped cookie would be overlaid onto
*their* first paint and replayed into *their* store.

So every entry is stamped with an **identity fingerprint**
(`Backpex.Preferences.LiveView.identity_fingerprint/2`): a keyed digest, over the
endpoint's `secret_key_base`, of

1. the identity your `:identity` resolver returned (with `nil` /
   `:unidentified` folded into one distinct anonymous value), and
2. the Phoenix session's CSRF token.

Both, because Backpex can host more than one store and they are not scoped
alike. One `:identity` resolver serves every prefix — the router picks the
*adapter* per prefix, not the identity — but `Backpex.Preferences.Adapters.Session`
(the default, and the whole store in a zero-config install) ignores identity
altogether and scopes by the **session**. Digesting only the identity would give
every user of an anonymous session-backed install the same fingerprint, which is
the bug. The CSRF token is the session's stable per-session secret: unchanged by
preference writes, and regenerated exactly when the session is renewed — which is
what `phx.gen.auth`'s `renew_session/1` does on login and logout.

Together they keep the cookie's scope at least as narrow as the narrowest store's.
An app that neither renews the session on login nor configures `:identity` gets
one fingerprint for both users — but it also hands them the same session, so the
Session adapter is already sharing the *stored* preferences between them; the
cookie leaks nothing the store does not.

The server renders the fingerprint into `data-preferences-identity` (pass
`preferences_identity={@preferences_identity}` to `app_shell`). The browser
discards the whole cookie when it does not match, and so does the disconnected
mount — which does not trust the browser to have discarded it, because that is
exactly where a planted cookie lands. The digest is keyed, so it exposes no user
id to the scripts that can read this cookie.

When there is no fingerprint to be had — no `secret_key_base`, a layout that does
not pass the assign, or the very first request of a brand-new session, whose CSRF
token `Plug.CSRFProtection` only writes back at the end of the response — Backpex
behaves as though the cookie did not exist: a first paint that may be one write
stale, never a write attributed to the wrong user.

Because the cookie is browser-written and unsigned, anything any script on the
origin can plant reaches a render. `Backpex.Preferences.Context.put_client/2`
therefore filters both client carriers — the cookie and the connect params —
before they become an overlay (the fingerprint is an *additional* gate, not a
replacement: it says who wrote a value, not that the value is sane):

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
| `resource:<Module>:metrics_visible`        | boolean  | Index view mount                         | `toggle_metrics` event                | `persist: [:metrics]`   |
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
  preferences_identity={@preferences_identity}
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
routing bulky per-resource state there. As a heads-up, the Session adapter
logs a warning when a single write pushes the stored tree past ~3KB — that
is your cue to route the heavy prefixes (per-resource column visibility,
saved filters, etc.) to a database-backed adapter before you hit the hard
limit.

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
broader ones and `:default` regardless of the order they appear in config.
Patterns:

- `"global.*"` — a wildcard: every key under the `global` prefix.
- `"global.theme"` — an exact key; beats `"global.*"`.
- `:default` — fallback when nothing else matches.

With no `:adapters` config, the router falls back to a single `:default` →
Session route so existing apps need no changes.

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
    {"resource:MyApp.PostLive:*", MyApp.Preferences.EctoAdapter, repo: MyApp.Repo},
    {"resource.*", Backpex.Preferences.Adapters.Session, []},
    {:default, Backpex.Preferences.Adapters.Session, []}
  ]
```

The narrower route owns every `MyApp.PostLive` key; every other resource still
goes to the session. Order does not matter — specificity decides.

`"*"` is only valid as the **final** segment. A bare `"*"`, or a pattern like
`"resource.*.columns"`, can never match a key, so Backpex raises at boot rather
than letting the keys you meant to route quietly land somewhere else. Use
`:default` to match every key.

There is no suffix or predicate matching: an adapter owns a **prefix** of the
key space. That is what lets a subtree read (`get_map/3`, which resolves the
prefix through the same routes as the keys beneath it) name a single owner and
see all of its own writes.

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
- `put/4` — persist one value. Return `{:ok, :persisted}` when you stored it
  yourself (the usual case for a DB adapter), or `{:ok, {:put_session, key,
  map}}` to ask the caller to write `map` into the Phoenix session.

The side-effect protocol is what keeps adapters pure. They don't touch
`Plug.Conn` — they describe what the caller should do. This is what lets
the controller compose cross-adapter batch writes and lets server-side code
dispatch the same adapters without an HTTP request.

`{:put_session, _, _}` is only honorable on a `%Plug.Conn{}` —
`Plug.Session` is HTTP-only. An adapter that stores in the session must
return `{:error, :requires_http}` when called outside a controller (the
Session adapter does exactly this), so the dispatcher can round-trip the
write through the browser instead.

Batch writes are **best-effort, first-error-wins**: on the first adapter
error the dispatcher halts, returns `{:error, {key, reason}}`, and the
controller responds `422 {ok: false, error: %{key: _, reason: _}}` without
applying any session-backed side effects collected earlier in the batch.
Adapters that persist eagerly (e.g. a DB-backed adapter that wrote via
`Repo.insert!`) may have already committed earlier writes — the adapter
behaviour has no rollback primitive, so callers should treat partial
success as possible.

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
    {:ok, :persisted}
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

    {:ok, :persisted}
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
  Writes every time the order changes.
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

If `nil` is itself a value your preference can legitimately hold, pass a
sentinel instead — `Backpex.Preferences.get(session, key, default: :__unset__)`
— and match on that.

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
HTTP response — any response. `200 {ok: true}`, the `200 {ok: false, error:
{reason: "unidentified"}}` an anonymous visitor gets, and a `422` all count: the
server has seen the write and decided on it, so replaying it is pointless and
keeping a client overlay would pin the value forever. Until then, the browser is
the only party that knows what the user picked, and it has to carry that
knowledge to the server itself.

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
reload, not just the sidebar. A pending write only ever applies to the identity
that made it: see [Scoping the pending cookie to a
user](#scoping-the-pending-cookie-to-a-user).

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
cookie is written for every key regardless, so the choice below is not about the
first paint after a reload — that is always correct — but about whether the
value must survive a `live_redirect`.

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
  anyway. Backpex's filters and order are the example: they live in the URL, and
  pinning them in the mirror would fight live navigation.
- The server is always authoritative on every render — e.g. a DB-backed
  preference read fresh from Ecto in `mount/3`. There's no frozen snapshot
  to override.
- You need cross-tab consistency within the browser — `sessionStorage` is
  per-tab; a mirror there will diverge between two tabs of the same admin.
  (`backpex_prefs` *is* shared across tabs, but it only ever holds a write for
  as long as its POST is in flight, so it cannot pin a divergence.)

An unmirrored key still gets a correct first paint after a fast reload. What it
gives up is the `live_redirect` guarantee.

### Server-originated writes: `push_write`

The mirror also covers preferences the **server** writes via
`Backpex.Preferences.LiveView.push_write/4`, such as column and metric
visibility. These are server-rendered content (a hidden column is not in
the DOM at all), so a client hook cannot re-apply them the way the sidebar
hooks re-apply CSS state — the server has to know before it renders:

1. `push_write(socket, key, value, mirror: :session)` tells the
   `BackpexPreferences` hook to mirror the value into sessionStorage in
   addition to the HTTP POST.
2. Every subsequent join sends the mirrored values in the connect params.
3. `Backpex.Preferences.LiveView.mount_context/2` folds them into the
   `Context`, where `get/3` and `get_map/3` prefer them over the stored
   value — so the first render already reflects the toggle.

This only matters for the Session adapter's frozen-snapshot staleness; a
DB-backed adapter reads fresh at every mount, and there the mirrored values
simply match what the adapter returns.

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
