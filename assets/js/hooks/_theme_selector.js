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
 * `<html>`. Changes are persisted via BackpexPreferences with
 * `mirror: 'session'`, like every other server-rendered preference.
 *
 * The mirror is what the theme-selector radio's `checked` state needs. That
 * radio DOES live inside the LiveView-rendered tree, so without the mirror the
 * connected render — and every live_redirect after it — re-checks the OLD radio
 * whenever the write has not landed in the connect-time session snapshot, i.e.
 * the connected render contradicts the dead render. The `data-theme` attribute
 * on `<html>` itself is a separate matter: it sits outside the LiveView root
 * and is only re-rendered on a full page load, where the `backpex_prefs` cookie
 * already makes the dead render correct.
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

      // Persist via BackpexPreferences — see the module-level comment above
      // for why the theme is mirrored.
      BackpexPreferences.set('global.theme', selectedTheme.value, { mirror: 'session' })
    }
  },

  destroyed () {
    this.el.removeEventListener('backpex:theme-change', this.boundHandleThemeChange)
  }
}
