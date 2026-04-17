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
│   All-or-nothing apply: {ok: true} or {ok: false, errors: […]}           │
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

## Built-in preference keys

Every key Backpex reads or writes is listed here. Third-party code should
prefix its own keys with `custom.` to avoid colliding with Backpex.

| Key                                        | Type     | Read at                                                  | Written at                                                   | Opt-in?                                                        |
|--------------------------------------------|----------|----------------------------------------------------------|--------------------------------------------------------------|----------------------------------------------------------------|
| `global.theme`                             | string   | `Backpex.InitAssigns`                                    | JS theme selector (`Backpex.ThemeSelectorPlug`)              | always on                                                      |
| `global.sidebar_open`                      | boolean  | `Backpex.InitAssigns`                                    | JS sidebar toggle                                            | always on                                                      |
| `global.sidebar_section.<id>`              | boolean  | `Backpex.InitAssigns` (via `get_map/3`)                  | JS sidebar section toggle                                    | always on                                                      |
| `resource:<Module>:columns`                | map      | `Backpex.LiveResource.Index` at mount                    | `toggle_column` event in `Backpex.LiveResource.Index`        | `persist: [:columns]`                                          |
| `resource:<Module>:metrics_visible`        | boolean  | `Backpex.LiveResource.Index` at mount                    | `toggle_metrics` event in `Backpex.LiveResource.Index`       | always on                                                      |
| `resource:<Module>:order`                  | map      | `Backpex.LiveResource.Index` at mount (fallback)         | `handle_params` in `Backpex.LiveResource.Index` (on change)  | `persist: [:order]`                                            |
| `resource:<Module>:filters`                | map      | `Backpex.LiveResource.Index` at mount (fallback)         | `handle_params` in `Backpex.LiveResource.Index` (on change)  | `persist: [:filters]`                                          |

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
- `:default` — fallback when nothing else matches.

With no `:adapters` config, the router falls back to a single `:default` →
Session route so existing apps need no changes.

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

  def resolve(%Context{assigns: %{current_user: %{id: id}}}), do: id
  def resolve(%Context{conn: %Plug.Conn{} = conn}) do
    case Plug.Conn.get_session(conn, :user_id) do
      nil -> :unidentified
      id -> id
    end
  end

  def resolve(_ctx), do: :unidentified
end
```

The dispatcher calls the resolver once per read/write, memoizes the result
on the `Context`, and hands it to the adapter as `ctx.identity`. Return
`:unidentified` (or raise) when no user is logged in. Adapter reads treated
as "not found" and the caller falls back to the `:default` option; writes
return `{:error, :unidentified}` and the controller responds
`200 {ok: false, errors: [{…, :unidentified}]}`.

## Writing a custom adapter

Implement `Backpex.Preferences.Adapter`. Three callbacks:

- `get/3` — read one key. Return `{:ok, value}` or `{:ok, :not_found}`.
- `get_map/3` — read everything under a prefix as a nested map.
- `put/4` — persist one value; return a list of **side effects** for the
  caller to apply (`[:noop]` if you already persisted; `[{:put_session, k,
  map}]` when you need the caller to update the session).

The side-effect protocol is what keeps adapters pure. They don't touch
`Plug.Conn` — they describe what the caller should do. This is what lets the
controller implement all-or-nothing batch writes and lets server-side code
dispatch the same adapters without an HTTP request.

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

  schema "backpex_user_preferences" do
    field :user_id, :integer
    field :key,     :string
    field :value,   :map, default: %{}
    timestamps(type: :utc_datetime_usec)
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

    %UserPreference{}
    |> UserPreference.__struct__()
    |> Map.put(:user_id, user_id)
    |> Map.put(:key, key)
    |> Map.put(:value, wrap_value(value))
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

```elixir
# Migration: adds JSON columns to an existing user_settings table
alter table(:user_settings) do
  add :ordering_preferences,  :map, null: false, default: %{}
  add :filter_preferences,    :map, null: false, default: %{}
  add :column_visibility,     :map, null: false, default: %{}
end

defmodule MyApp.Preferences.EctoAdapter do
  @behaviour Backpex.Preferences.Adapter

  import Ecto.Query
  alias MyApp.Settings.UserSettings

  @column_map %{
    ["resource", _mod, "order"]   => :ordering_preferences,
    ["resource", _mod, "filters"] => :filter_preferences,
    ["resource", _mod, "columns"] => :column_visibility
  }

  @impl true
  def get(%{identity: :unidentified}, _key, _opts), do: {:ok, :not_found}
  def get(%{identity: user_id}, key, opts) do
    repo = Keyword.fetch!(opts, :repo)
    [_, module_name, _] = segments = Backpex.Preferences.Key.parse(key)

    column = segments_to_column(segments)

    case repo.one(from s in UserSettings, where: s.user_id == ^user_id, select: field(s, ^column)) do
      nil -> {:ok, :not_found}
      map -> {:ok, Map.get(map, module_name, :not_found) |> to_ok_not_found()}
    end
  end

  # get_map/3, put/4 follow the same "which column?" lookup.

  defp segments_to_column(["resource", _mod, "order"]),   do: :ordering_preferences
  defp segments_to_column(["resource", _mod, "filters"]), do: :filter_preferences
  defp segments_to_column(["resource", _mod, "columns"]), do: :column_visibility

  defp to_ok_not_found(:not_found), do: :not_found
  defp to_ok_not_found(value), do: value
end
```

This pattern matches apps that already manage preferences through a
purpose-shaped settings table; Backpex just becomes another writer.

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

### Before / after: migrating a custom macro

Apps that previously rolled their own persistence (custom `init_order`
callback backed by a DB table) can delete that scaffolding:

```elixir
# Before
use Backpex.LiveResource, adapter_config: [...]

def init_order(assigns), do: MyApp.OrderingSettings.fetch(assigns.current_user, __MODULE__)

def handle_event(...) do
  # ... hand-rolled write to MyApp.OrderingSettings ...
end
```

```elixir
# After
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

From a LiveView `handle_event`, use `Backpex.Preferences.put_async/3`:

```elixir
def handle_event("toggle_view_mode", _params, socket) do
  new_mode = if socket.assigns.view_mode == "grid", do: "list", else: "grid"

  {:ok, socket} = Backpex.Preferences.put_async(socket, "custom.dashboard.view_mode", new_mode)

  {:noreply, assign(socket, :view_mode, new_mode)}
end
```

Under the hood `put_async/3` tries the configured adapter first. When the
adapter is session-backed (no HTTP request in a LiveView event), it falls
back to a `push_event/3` round-trip so the browser persists via the
preferences controller on its next paint. DB-backed adapters just write
directly and return.

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
