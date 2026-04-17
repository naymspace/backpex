/**
 * BackpexPreferences - Unified preference persistence
 *
 * Handles all preference writes to the server. Supports:
 * - Direct calls from JS hooks: BackpexPreferences.set(key, value)
 * - LiveView push_events: push_event("backpex:set_preference", %{key, value})
 *
 * Features:
 * - Immediate persistence with keepalive (survives page navigation)
 * - Non-blocking async operation
 */

const BackpexPreferences = {
  endpointPath: null,
  csrfToken: null,

  /**
   * Initialize the preference manager.
   * Called by the LiveView hook on mount.
   */
  init (endpointPath) {
    this.endpointPath = endpointPath
    this.csrfToken = document.querySelector("meta[name='csrf-token']")?.content
  },

  /**
   * Set a preference value and persist immediately.
   * Called directly by JS hooks or via LiveView push_event.
   *
   * @param {string} key - Dot-notation key (e.g., "global.theme")
   * @param {any} value - Value to store
   */
  set (key, value) {
    this.persist(key, value)
  },

  /**
   * Persist a preference to the server immediately.
   * Uses keepalive to ensure request completes even during page navigation.
   */
  persist (key, value) {
    if (!this.endpointPath) {
      console.warn('BackpexPreferences: endpointPath not initialized')
      return
    }
    if (!this.csrfToken) {
      console.warn('BackpexPreferences: CSRF token not found')
      return
    }

    // Use keepalive to ensure request survives page navigation
    fetch(this.endpointPath, {
      method: 'POST',
      keepalive: true,
      headers: {
        'Content-Type': 'application/json',
        'x-csrf-token': this.csrfToken
      },
      body: JSON.stringify({ key, value })
    }).catch(error => {
      console.error('BackpexPreferences: failed to persist', error)
    })
  }
}

/**
 * LiveView hook that initializes BackpexPreferences
 * and listens for push_events from the server.
 *
 * Mount this hook on an element with data-preferences-path attribute.
 */
const BackpexPreferencesHook = {
  mounted () {
    BackpexPreferences.init(this.el.dataset.preferencesPath)

    this.handleEvent('backpex:set_preference', ({ key, value }) => {
      BackpexPreferences.set(key, value)
    })
  }
}

export default BackpexPreferencesHook
export { BackpexPreferences }
