/**
 * Hook for selecting a theme.
 */
export default {
  mounted () {
    const form = document.querySelector('#backpex-theme-selector-form')
    const storedTheme = window.localStorage.getItem('backpexTheme')

    // Marking current theme as active
    if (storedTheme != null) {
      const activeThemeRadio = form.querySelector(
        `input[name='theme-selector'][value='${storedTheme}']`
      )
      activeThemeRadio.checked = true
    }

    window.addEventListener('backpex:theme-change', this.handleThemeChange.bind(this))
  },
  // Event listener that handles the theme changes and store
  // the selected theme in the session and also in localStorage
  async handleThemeChange () {
    const form = document.querySelector('#backpex-theme-selector-form')
    const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute('content')
    const cookiePath = form.dataset.cookiePath
    const selectedTheme = form.querySelector(
      'input[name="theme-selector"]:checked'
    )

    if (selectedTheme) {
      window.localStorage.setItem('backpexTheme', selectedTheme.value)
      document.documentElement.setAttribute(
        'data-theme',
        selectedTheme.value
      )
      await fetch(cookiePath, {
        body: `select_theme=${selectedTheme.value}`,
        method: 'POST',
        headers: {
          'Content-type': 'application/x-www-form-urlencoded',
          'x-csrf-token': csrfToken
        }
      })
    }
  },
  // Call this from your app.js as soon as possible to minimize flashes with the old theme in some situations.
  setStoredTheme () {
    const storedTheme = window.localStorage.getItem('backpexTheme')

    if (storedTheme != null) {
      document.documentElement.setAttribute('data-theme', storedTheme)
    }
  },
  destroyed () {
    window.removeEventListener('backpex:theme-change', this.handleThemeChange.bind(this))
  }
}
