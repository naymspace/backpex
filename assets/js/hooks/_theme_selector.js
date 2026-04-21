import { BackpexPreferences } from './_preferences'

/**
 * Hook for selecting a theme.
 * Initial theme is server-rendered via data-theme attribute on <html>.
 * Changes are persisted via BackpexPreferences.
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
    // Just set up the change listener
    this.boundHandleThemeChange = this.handleThemeChange.bind(this)
    window.addEventListener('backpex:theme-change', this.boundHandleThemeChange)
  },

  handleThemeChange () {
    const form = document.querySelector('#backpex-theme-selector-form')
    if (!form) return

    const selectedTheme = form.querySelector(
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
    window.removeEventListener('backpex:theme-change', this.boundHandleThemeChange)
  }
}
