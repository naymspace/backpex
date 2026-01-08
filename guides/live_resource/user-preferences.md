# User Preferences

Backpex includes a cookie-based preference system that persists UI state across page reloads without flickering. This system stores preferences in the Phoenix session and server-renders the correct initial state.

## How It Works

```
                                    INITIAL PAGE LOAD
    ┌─────────────────────────────────────────────────────────────────────────┐
    │                                                                         │
    │   Browser Request          Phoenix Session           Server Render      │
    │   ───────────────          ───────────────           ─────────────      │
    │                                                                         │
    │   ┌─────────┐    Cookie    ┌─────────────────┐      ┌───────────────┐  │
    │   │ Browser │───────────▶  │ Backpex.        │─────▶│ HTML with     │  │
    │   │         │              │ InitAssigns     │      │ correct state │  │
    │   └─────────┘              └─────────────────┘      └───────────────┘  │
    │                                    │                                    │
    │                                    ▼                                    │
    │                            Assigns populated:                           │
    │                            • @current_theme                             │
    │                            • @sidebar_open                              │
    │                            • @sidebar_section_states                    │
    │                                                                         │
    └─────────────────────────────────────────────────────────────────────────┘

                                  USER CHANGES STATE
    ┌─────────────────────────────────────────────────────────────────────────┐
    │                                                                         │
    │   1. Update UI             2. Persist to Cookie     3. Next Page Load   │
    │   ────────────             ───────────────────      ────────────────    │
    │                                                                         │
    │   ┌───────────┐            ┌───────────────────┐    ┌───────────────┐  │
    │   │ JS Toggle │──────────▶ │ BackpexPreferences│───▶│ Server reads  │  │
    │   │ (instant) │            │ .set(key, value)  │    │ cookie, renders│  │
    │   └───────────┘            └───────────────────┘    │ correct state │  │
    │         │                          │                └───────────────┘  │
    │         │                          ▼                                    │
    │         │                  POST /backpex_preferences                    │
    │         │                  (async, keepalive)                           │
    │         ▼                                                               │
    │   UI updates immediately                                                │
    │   (no wait for server)                                                  │
    │                                                                         │
    └─────────────────────────────────────────────────────────────────────────┘
```

**Key benefits:**
- **No flickering**: Server renders the correct initial state from session cookies
- **Instant feedback**: UI updates immediately, persistence happens asynchronously
- **Reliable persistence**: Uses `keepalive: true` to ensure requests survive page navigation
- **Unified API**: All preferences use the same storage mechanism

## Built-in Preferences

Backpex automatically manages these preferences:

| Preference | Key | Type | Default |
|------------|-----|------|---------|
| Theme | `global.theme` | string | `nil` |
| Sidebar open/closed | `global.sidebar_open` | boolean | `true` |
| Sidebar section states | `global.sidebar_section.<id>` | boolean | `true` |
| Column visibility | `resource.<Name>.columns` | map | `%{}` |
| Metrics visibility | `resource.<Name>.metrics_visible` | boolean | `true` |

These preferences are automatically populated by `Backpex.InitAssigns` and persisted when users interact with the UI.

## Using Preferences in Your Layout

The `Backpex.InitAssigns` hook provides these assigns to your LiveViews:

```elixir
# These assigns are available in your layout:
@current_theme           # "light", "dark", etc.
@sidebar_open            # true or false
@sidebar_section_states  # %{"blog" => true, "settings" => false}
```

Use them in your layout template:

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
      <!-- sidebar items -->
    </Backpex.HTML.Layout.sidebar_section>
  </:sidebar>
  <!-- content -->
</Backpex.HTML.Layout.app_shell>
```

## Custom Preferences

You can use the preference system for your own UI state. This is useful for features like:
- Custom panel expand/collapse states
- User-specific view modes (list vs. grid)
- Saved filter configurations
- Any UI state you want to persist

### Key Format

Preferences use dot-notation keys with namespaces:

- `global.*` - Application-wide preferences
- `resource.<Name>.*` - Per-resource preferences
- `custom.*` - Your custom preferences (recommended namespace)

### Reading Custom Preferences (Server-Side)

Use `Backpex.Preferences.get/3` in your LiveView or component:

```elixir
defmodule MyAppWeb.DashboardLive do
  use MyAppWeb, :live_view

  def mount(_params, session, socket) do
    # Read a custom preference with a default value
    view_mode = Backpex.Preferences.get(session, "custom.dashboard.view_mode", default: "grid")

    {:ok, assign(socket, :view_mode, view_mode)}
  end
end
```

For nested values, use `Backpex.Preferences.get_map/2`:

```elixir
# Get all panel states at once
panel_states = Backpex.Preferences.get_map(session, "custom.dashboard.panels")
# => %{"stats" => true, "charts" => false, "activity" => true}
```

### Writing Custom Preferences (Client-Side)

From JavaScript, use the `BackpexPreferences` API:

```javascript
import { BackpexPreferences } from 'backpex'

// Set a preference (persisted asynchronously)
BackpexPreferences.set('custom.dashboard.view_mode', 'list')

// Set multiple preferences (batched into single request)
BackpexPreferences.set('custom.dashboard.panels.stats', true)
BackpexPreferences.set('custom.dashboard.panels.charts', false)
```

### Writing Custom Preferences (Server-Side via LiveView)

From LiveView, use `push_event` to trigger the JavaScript persistence:

```elixir
def handle_event("toggle_view_mode", _params, socket) do
  new_mode = if socket.assigns.view_mode == "grid", do: "list", else: "grid"

  socket =
    socket
    |> assign(:view_mode, new_mode)
    |> push_event("backpex:set_preference", %{
      key: "custom.dashboard.view_mode",
      value: new_mode
    })

  {:noreply, socket}
end
```

## Complete Example: Custom Collapsible Panel

Here's a complete example of a custom collapsible panel that persists its state:

### 1. Create a custom InitAssigns hook

Extend `Backpex.InitAssigns` to include your custom preferences:

```elixir
defmodule MyAppWeb.InitAssigns do
  import Phoenix.LiveView

  def on_mount(:default, params, session, socket) do
    # First, call Backpex's InitAssigns
    {:cont, socket} = Backpex.InitAssigns.on_mount(:default, params, session, socket)

    # Add your custom preferences
    panel_states = Backpex.Preferences.get_map(session, "custom.panels")

    {:cont, assign(socket, :panel_states, panel_states)}
  end
end
```

Update your router to use your custom hook:

```elixir
live_session :default, on_mount: MyAppWeb.InitAssigns do
  # your routes
end
```

### 2. Create the panel component

```elixir
defmodule MyAppWeb.Components.CollapsiblePanel do
  use Phoenix.Component

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :panel_states, :map, default: %{}
  slot :inner_block, required: true

  def collapsible_panel(assigns) do
    open = Map.get(assigns.panel_states, assigns.id, true)
    assigns = assign(assigns, :open, open)

    ~H"""
    <div class="border rounded-lg" data-panel-id={@id}>
      <button
        type="button"
        class="w-full p-4 flex justify-between items-center"
        phx-click={toggle_panel(@id, @open)}
      >
        <span class="font-semibold">{@title}</span>
        <span class={["transition-transform", @open && "rotate-180"]}>▼</span>
      </button>
      <div class={["p-4 border-t", !@open && "hidden"]}>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  defp toggle_panel(id, currently_open) do
    # This JS command updates the UI and persists the preference
    Phoenix.LiveView.JS.new()
    |> Phoenix.LiveView.JS.toggle(to: "[data-panel-id='#{id}'] > div:last-child")
    |> Phoenix.LiveView.JS.toggle_class("rotate-180", to: "[data-panel-id='#{id}'] button span:last-child")
    |> Phoenix.LiveView.JS.dispatch("backpex:persist-panel", detail: %{id: id, open: !currently_open})
  end
end
```

### 3. Add JavaScript to handle persistence

In your `app.js`:

```javascript
import { BackpexPreferences } from 'backpex'

// Listen for panel toggle events
window.addEventListener('backpex:persist-panel', (event) => {
  const { id, open } = event.detail
  BackpexPreferences.set(`custom.panels.${id}`, open)
})
```

### 4. Use the component

```heex
<.collapsible_panel id="stats" title="Statistics" panel_states={@panel_states}>
  <p>Your statistics content here...</p>
</.collapsible_panel>

<.collapsible_panel id="activity" title="Recent Activity" panel_states={@panel_states}>
  <p>Activity feed here...</p>
</.collapsible_panel>
```

The panel states will now persist across page reloads without any flickering.
