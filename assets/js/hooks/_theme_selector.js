import { BackpexPreferences } from './_preferences'

/**
 * Hook for selecting a theme.
 * Initial theme is server-rendered via data-theme attribute on <html>.
 * Changes are persisted via BackpexPreferences.
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

      // Persist to cookie via BackpexPreferences
      BackpexPreferences.set('global.theme', selectedTheme.value)
    }
  },

  destroyed () {
    window.removeEventListener('backpex:theme-change', this.boundHandleThemeChange)
  }
}
