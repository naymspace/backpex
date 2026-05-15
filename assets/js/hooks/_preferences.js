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
 * - Optional sessionStorage mirroring for hooks whose UI chrome is re-rendered
 *   from a session snapshot that LiveView freezes at websocket-connect time.
 *   See the `mirror: 'session'` option on `set/3` and the matching `get/2`
 *   below — and the "Writing a JS hook that persists preferences" section
 *   of the user-preferences guide for the full rationale.
 */

// All mirrored values share this prefix so a devtools inspection of
// sessionStorage is legible and one call site can clear everything if needed.
const SESSION_PREFIX = 'backpex.prefs.'

function sessionKey (key) {
  return SESSION_PREFIX + key
}

// Best-effort read. Returns the raw string, or null if sessionStorage is
// unavailable (private mode, disabled) or the key is absent.
function readSession (key) {
  try {
    return sessionStorage.getItem(sessionKey(key))
  } catch {
    return null
  }
}

// Best-effort write. Silently drops writes if sessionStorage is unavailable
// or quota-exceeded — the HTTP POST is still fired and remains authoritative
// on the next fresh connect.
function writeSession (key, value) {
  try {
    sessionStorage.setItem(sessionKey(key), value)
  } catch {
    // sessionStorage may be unavailable (private mode, quota); best effort only
  }
}

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
   * Read a preference, preferring the sessionStorage mirror over the
   * caller-provided fallback. Only meaningful for keys that were written
   * with `{ mirror: 'session' }` — keys persisted on the server alone will
   * always return `fallback` here.
   *
   * Booleans and numbers deserialize from their `String(value)` form;
   * strings pass through; everything else round-trips through JSON.
   *
   * The fallback's runtime type drives deserialization, so callers always
   * get a value of the same shape they passed in.
   *
   * @param {string} key - Dot-notation key (e.g., "global.sidebar_open")
   * @param {boolean|number|string|object|null|undefined} fallback - Value to
   *   return when the mirror is absent or sessionStorage is unavailable.
   * @returns {*} The stored value or `fallback`.
   */
  get (key, fallback) {
    const raw = readSession(key)
    if (raw === null) return fallback

    if (typeof fallback === 'boolean') return raw === 'true'
    if (typeof fallback === 'number') {
      const n = Number(raw)
      return Number.isNaN(n) ? fallback : n
    }
    if (typeof fallback === 'string') return raw

    // Objects, arrays, null, undefined fallbacks → treat the mirror as JSON.
    try {
      return JSON.parse(raw)
    } catch {
      return fallback
    }
  },

  /**
   * Set a preference value and persist immediately.
   * Called directly by JS hooks or via LiveView push_event.
   *
   * When `opts.mirror === 'session'` the value is written to sessionStorage
   * *before* the HTTP POST, so the client-authoritative state survives the
   * hook re-mount that LiveView performs on `live_redirect` between
   * LiveViews (the server reads its session snapshot from the websocket
   * handshake, which is frozen at connect time and doesn't see writes the
   * HTTP endpoint just committed to the cookie).
   *
   * `opts.mirror === false` (or omitting `opts` entirely) keeps the legacy
   * behavior: HTTP POST only, no local mirror. This is the right choice
   * whenever the server is the authoritative source on every render
   * (e.g. a DB-backed preference read fresh from Ecto).
   *
   * @param {string} key - Dot-notation key (e.g., "global.theme")
   * @param {any} value - Value to store
   * @param {{ mirror?: 'session' | false }} [opts]
   */
  set (key, value, opts = {}) {
    if (opts.mirror === 'session') {
      const serialized = (typeof value === 'string')
        ? value
        : (typeof value === 'boolean' || typeof value === 'number')
            ? String(value)
            : JSON.stringify(value)
      writeSession(key, serialized)
    }

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
