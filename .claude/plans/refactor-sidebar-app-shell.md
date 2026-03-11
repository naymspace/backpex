# Refactor Sidebar / App Shell for Flexible Sections

## Context

The `app_shell` component wraps the `:sidebar` slot content inside a hardcoded `<nav><ul>...</ul></nav>` structure (both desktop and mobile). This constrains sidebar content to only `<li>` elements, making it impossible to have multiple independent sections, pin content to the bottom, or add non-list content like dividers or headings.

**Goal**: Allow users to compose the sidebar freely with multiple sections (e.g., main nav at top, admin section pinned to bottom via `mt-auto`).

## Changes

### 1. Add `sidebar_nav` component (`lib/backpex/html/layout.ex`)

New component that provides the `<nav><ul class="menu">` wrapper users currently get for free:

```elixir
attr :label, :string, required: true  # aria-label for the <nav>
attr :class, :string, default: nil

slot :inner_block

def sidebar_nav(assigns) do
  ~H"""
  <nav aria-label={@label} class={@class}>
    <ul class="menu">
      {render_slot(@inner_block)}
    </ul>
  </nav>
  """
end
```

Place after the existing `sidebar_section` component (~line 482).

### 2. Modify `app_shell` sidebar rendering (`lib/backpex/html/layout.ex`, lines 51-61 and 88-98)

Remove the `<nav><ul>` wrapper. Replace with a flex-column container that gives users full layout control.

**Desktop sidebar** (lines 51-61): `<nav class="menu ...">` → `<aside class="... md:flex flex-col">`
- Remove `menu` class (moves to `sidebar_nav`)
- Remove `<ul>` wrapper
- Change `hidden ... md:block` to `hidden ... md:flex` + add `flex-col`
- Change `overflow-y-scroll` to `overflow-y-auto`
- Remove the navigation-specific `aria-label`, use `Backpex.__("Sidebar", @live_resource)` instead

**Mobile sidebar** (lines 88-98): Same transformation
- `<nav class="bg-base-100 menu ...">` → `<aside class="bg-base-100 flex flex-col ...">`
- Remove `<ul>` wrapper

### 3. Update demo layout (`demo/lib/demo_web/components/layouts/admin.html.heex`)

Wrap existing sidebar items in `sidebar_nav` and add a bottom-pinned section to showcase the new flexibility:

```heex
<:sidebar>
  <Backpex.HTML.Layout.sidebar_nav label="Main navigation">
    <!-- existing sidebar_item and sidebar_section entries -->
  </Backpex.HTML.Layout.sidebar_nav>

  <Backpex.HTML.Layout.sidebar_nav label="Admin" class="mt-auto">
    <Backpex.HTML.Layout.sidebar_item current_url={@current_url} navigate="/admin/helpdesk/tickets">
      <Backpex.HTML.CoreComponents.icon name="hero-lifebuoy" class="size-5" /> Helpdesk
    </Backpex.HTML.Layout.sidebar_item>
  </Backpex.HTML.Layout.sidebar_nav>
</:sidebar>
```

### 4. Update generator template (`priv/templates/layouts/admin.html.heex`)

Wrap the commented-out example in `sidebar_nav`:

```heex
<:sidebar>
  <Backpex.HTML.Layout.sidebar_nav label="Main navigation">
    <!-- Example Sidebar Item -->
  </Backpex.HTML.Layout.sidebar_nav>
</:sidebar>
```

### 5. Update installation guide (`guides/get_started/installation.md`)

Update sidebar examples at lines ~159 and ~363 to use `sidebar_nav` wrapper.

### No changes needed

- **JS hook** (`assets/js/hooks/_sidebar_sections.js`): Uses `this.el.querySelectorAll('[data-section-id]')` on `#backpex-app-shell` — works at any DOM depth, no changes needed.
- **`sidebar_item`** and **`sidebar_section`** components: Still render `<li>` elements, which is correct inside `sidebar_nav`'s `<ul>`.

## Files to modify

| File | Change |
|------|--------|
| `lib/backpex/html/layout.ex` | Add `sidebar_nav/1`; modify `app_shell/1` desktop+mobile sidebar |
| `demo/lib/demo_web/components/layouts/admin.html.heex` | Wrap items in `sidebar_nav`; add bottom-pinned section |
| `priv/templates/layouts/admin.html.heex` | Wrap example in `sidebar_nav` |
| `guides/get_started/installation.md` | Update sidebar code examples |

## Migration for users

Wrap existing `:sidebar` slot content in `<Backpex.HTML.Layout.sidebar_nav label="Main navigation">`:

```heex
<!-- Before -->
<:sidebar>
  <Backpex.HTML.Layout.sidebar_item ...>Users</Backpex.HTML.Layout.sidebar_item>
</:sidebar>

<!-- After -->
<:sidebar>
  <Backpex.HTML.Layout.sidebar_nav label="Main navigation">
    <Backpex.HTML.Layout.sidebar_item ...>Users</Backpex.HTML.Layout.sidebar_item>
  </Backpex.HTML.Layout.sidebar_nav>
</:sidebar>
```

## Verification

1. Run `mix compile --warnings-as-errors` to verify compilation
2. Run `mix lint` for Backpex linting
3. Run `docker compose exec -T app yarn lint` for demo linting
4. Visually verify via Chrome DevTools MCP at http://localhost:4000:
   - Desktop: sidebar renders correctly with sections, bottom section pinned
   - Mobile: hamburger menu opens drawer with same layout
   - Collapsible sections still work (Blog section toggle)
5. Run demo tests: `docker compose exec -T app mix test`
