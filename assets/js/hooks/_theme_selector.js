import { BackpexPreferences } from './_preferences'

/**
 * Hook for selecting a theme.
 *
 * Mounted on the inner `<form id="backpex-theme-selector-form">` element
 * rather than the surrounding dropdown wrapper: the `<.dropdown>` component
 * hardcodes `phx-hook="BackpexDropdown"` on its root, so passing a second
 * `phx-hook` via `@rest` produced a duplicate attribute that the browser
 * silently dropped. Mounting on the form sidesteps the collision, lets
 * `this.el` be the form directly, and scopes the change listener to it.
 *
 * Initial theme is server-rendered via the `data-theme` attribute on
 * `<html>`. Changes are persisted via BackpexPreferences.
 *
 * This hook deliberately does NOT use `mirror: 'session'` even though the
 * server reads `global.theme` at LiveView mount from a potentially-stale
 * session snapshot (see `_sidebar.js` for the full rationale). The reason:
 * the user-visible theme is the `data-theme` attribute on `<html>`, which
 * lives outside the LiveView root and is therefore never re-rendered on
 * live_redirect — a stale read only misleads the internal theme-selector
 * radio's `checked` attribute for one paint until the user reopens the
 * menu. Not worth the sessionStorage overhead. If we ever move theme state
 * inside the LiveView-rendered tree, switch to mirror: 'session'.
 */
export default {
  mounted () {
    // Initial theme already applied via server-rendered data-theme attribute
    // Just set up the change listener, scoped to the form element itself.
    this.boundHandleThemeChange = this.handleThemeChange.bind(this)
    this.el.addEventListener('backpex:theme-change', this.boundHandleThemeChange)
  },

  handleThemeChange () {
    const selectedTheme = this.el.querySelector(
      'input[name="theme-selector"]:checked'
    )

    if (selectedTheme) {
      // Update DOM immediately (optimistic)
      document.documentElement.setAttribute('data-theme', selectedTheme.value)

      // Persist to cookie via BackpexPreferences — no mirror needed, see
      // the module-level comment above.
      BackpexPreferences.set('global.theme', selectedTheme.value)
    }
  },

  destroyed () {
    this.el.removeEventListener('backpex:theme-change', this.boundHandleThemeChange)
  }
}
