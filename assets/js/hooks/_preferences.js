/**
 * BackpexPreferences - Unified preference persistence
 *
 * Handles all preference writes to the server. Supports:
 * - Direct calls from JS hooks: BackpexPreferences.set(key, value)
 * - LiveView push_events: push_event("backpex:set_preference", %{key, value})
 *
 * PRECEDENCE RULE, stated once: the client overrides the server exactly when
 * it holds a write the server has not acknowledged. "Acknowledged" means the
 * preferences POST for that key came back with an HTTP response — any
 * response, see `persist/3`.
 *
 * Two carriers deliver that overlay, because a page can be rendered over two
 * different transports and each transport can only see one of them:
 *
 * - The `backpex_prefs` COOKIE reaches the document GET, i.e. the disconnected
 *   ("dead") render. It holds unacknowledged writes ONLY. `document.cookie` is
 *   written synchronously inside the click handler, so it rides the very next
 *   request — including a reload fired milliseconds later, long before the
 *   keepalive POST's `Set-Cookie` has updated the session. Without it the dead
 *   render paints the pre-toggle state and LiveView corrects it a frame later:
 *   the flash.
 * - The sessionStorage MIRROR reaches the websocket join via `connectParams()`.
 *   It is the only carrier that exists on a `live_redirect`, which makes no HTTP
 *   request at all: the server reads a session snapshot frozen at connect time
 *   and cannot see writes made since. Opt-in per key via `mirror: 'session'`.
 *
 * Both feed the same server-side `Backpex.Preferences.Context` client overlay,
 * so the dead render and the connected render derive the state from the same
 * values and agree by construction. See the "Writing a JS hook that persists
 * preferences" section of the user-preferences guide for the full rationale.
 */

// All mirrored values share this prefix so a devtools inspection of
// sessionStorage is legible and one call site can clear everything if needed.
const SESSION_PREFIX = 'backpex.prefs.'

// The pending-write cookie. Read by the disconnected mount
// (Backpex.Preferences.LiveView.client_cookie/0 — keep the names aligned).
//
// Not HttpOnly by necessity: only JS can write it synchronously, which is the
// entire point. Path `/` is deliberate — LiveResource routes may live under a
// different router scope than the preferences endpoint, so a narrower path
// risks the dead render never seeing the cookie. It is short-lived and
// normally empty, and it is only ever an input to a *render*, never to an
// adapter write.
const COOKIE_NAME = 'backpex_prefs'
const COOKIE_MAX_AGE = 300
// Stay well under the ~4KB per-cookie browser budget, which is also charged
// against the session cookie the Session adapter writes.
const COOKIE_MAX_BYTES = 3072

function sessionKey (key) {
  return SESSION_PREFIX + key
}

// The wire format for a single preference value. Booleans and numbers go over
// as their `String(value)` form, strings pass through unchanged, everything
// else round-trips through JSON. `get/2` reverses this using the fallback's
// runtime type.
function serialize (value) {
  if (typeof value === 'string') return value
  if (typeof value === 'boolean' || typeof value === 'number') return String(value)
  return JSON.stringify(value)
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

function cookieAttributes (maxAge) {
  const secure = window.location.protocol === 'https:' ? '; Secure' : ''
  return `; path=/; max-age=${maxAge}; SameSite=Lax${secure}`
}

// The unacknowledged writes this browser is holding, as a { key: value } map.
// Any malformed value degrades to `{}` — the cookie is client-written and a
// third-party script or a truncated write must never throw here.
function readPending () {
  const entry = document.cookie
    .split('; ')
    .find((cookie) => cookie.startsWith(`${COOKIE_NAME}=`))

  if (!entry) return {}

  try {
    const decoded = JSON.parse(decodeURIComponent(entry.slice(COOKIE_NAME.length + 1)))
    if (!decoded || typeof decoded !== 'object' || Array.isArray(decoded)) return {}
    return decoded
  } catch {
    return {}
  }
}

// Serializes the whole pending map into the cookie, deleting it when empty so
// the common case (nothing in flight) costs no bytes on any request.
function writePendingMap (map) {
  const pending = { ...map }
  let encoded = encodeURIComponent(JSON.stringify(pending))

  // Evict oldest-first until it fits. JS objects preserve string-key insertion
  // order, so `Object.keys()[0]` is the least recent write — the newest user
  // action always keeps the fast path; an evicted key merely regresses to a
  // stale first paint after a reload inside the race window.
  while (encoded.length > COOKIE_MAX_BYTES && Object.keys(pending).length > 1) {
    delete pending[Object.keys(pending)[0]]
    encoded = encodeURIComponent(JSON.stringify(pending))
  }

  if (encoded.length > COOKIE_MAX_BYTES) {
    console.warn(
      'BackpexPreferences: pending preference write exceeds the cookie budget; ' +
      'the first render after a reload may be stale until the POST lands.'
    )
    return
  }

  if (Object.keys(pending).length === 0) {
    document.cookie = `${COOKIE_NAME}=${cookieAttributes(0)}`
    return
  }

  document.cookie = `${COOKIE_NAME}=${encoded}${cookieAttributes(COOKIE_MAX_AGE)}`
}

// Records a write the server has not seen yet. Re-inserts the key so it counts
// as the newest entry for eviction.
function markPending (key, value) {
  const pending = readPending()
  delete pending[key]
  pending[key] = value
  writePendingMap(pending)
}

// Retires a write the server has acknowledged.
//
// Only retires the entry if the cookie still holds the value that was actually
// POSTed. The `_seq` guard in `persist/3` cannot cover this on its own: it
// lives in one page's JS context, while the cookie is shared by every tab on
// the origin. Without the value check, a replay finishing in tab B could retire
// a newer, still-unacknowledged write that tab A made in the meantime — and the
// server would then be free to overrule a choice the user just made.
function clearPending (key, value) {
  const pending = readPending()
  if (!(key in pending)) return
  if (JSON.stringify(pending[key]) !== JSON.stringify(value)) return
  delete pending[key]
  writePendingMap(pending)
}

const BackpexPreferences = {
  endpointPath: null,
  csrfToken: null,
  // Whether connectParams() has run for this page load. Set on the first
  // LiveView join, which is also where the mirror is primed from the cookie.
  connectParamsCalled: false,
  // Whether the pending writes have been replayed for this page load.
  replayCalled: false,
  // Per-key write counter. Guards the ack: the response to an *earlier* POST
  // must not retire a *later* write to the same key.
  _seq: {},

  /**
   * Initialize the preference manager.
   * Called by the LiveView hook on mount.
   */
  init (endpointPath) {
    this.endpointPath = endpointPath
    this.csrfToken = document.querySelector("meta[name='csrf-token']")?.content
  },

  /**
   * Name of the cookie carrying this browser's unacknowledged preference
   * writes. A wire contract with `Backpex.Preferences.LiveView.client_cookie/0`.
   *
   * @returns {string}
   */
  cookieName () {
    return COOKIE_NAME
  },

  /**
   * Whether this browser holds a write for `key` that the server has not
   * acknowledged yet.
   *
   * The gate any hook must check before adopting a server-rendered attribute:
   * a render whose session predates the pending write carries the OLD value,
   * and adopting it would undo the user's click.
   *
   * @param {string} key - Dot-notation key (e.g., "global.sidebar_open")
   * @returns {boolean}
   */
  isPending (key) {
    return key in readPending()
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
   * The value is recorded in the `backpex_prefs` cookie *before* the POST is
   * fired. That write is synchronous, so it is attached to the next request
   * the browser makes — including a reload that lands inside the POST's
   * round-trip window, whose session cookie is still one write behind. The
   * disconnected mount reads the cookie and renders the user's actual state.
   * The entry retires as soon as the POST responds (see `persist/3`).
   *
   * When `opts.mirror === 'session'` the value is *additionally* written to
   * sessionStorage, where it survives the whole page load. That is what keeps
   * client-authoritative state alive across the hook re-mount LiveView performs
   * on `live_redirect` between LiveViews: no HTTP request happens there, so the
   * cookie plays no part, and the server reads its session snapshot from the
   * websocket handshake, which is frozen at connect time.
   *
   * `opts.mirror === false` (or omitting `opts` entirely) keeps the value out
   * of the long-lived mirror. The right choice whenever the server is
   * authoritative on every render — for example filters and order, which
   * round-trip through the URL and must not be pinned across live navigation.
   * Such keys still get the short-lived pending cookie, so their first paint
   * after a fast reload is correct too.
   *
   * @param {string} key - Dot-notation key (e.g., "global.theme")
   * @param {any} value - Value to store
   * @param {{ mirror?: 'session' | false }} [opts]
   */
  set (key, value, opts = {}) {
    if (opts.mirror === 'session') writeSession(key, serialize(value))

    const seq = (this._seq[key] || 0) + 1
    this._seq[key] = seq

    this.persist(key, value, seq)
  },

  /**
   * All sessionStorage-mirrored preferences as a { key: value } object.
   *
   * Values stored as `String(boolean|number)` or JSON deserialize back to
   * their original type; plain strings that aren't valid JSON pass through
   * unchanged. Used by the hook to push the per-tab authoritative state
   * back to the server after a live-navigation re-mount, whose session
   * snapshot is frozen at websocket-connect time.
   *
   * @returns {Object<string, any>}
   */
  mirroredEntries () {
    const entries = {}
    try {
      for (let i = 0; i < sessionStorage.length; i++) {
        const storageKey = sessionStorage.key(i)
        if (storageKey && storageKey.startsWith(SESSION_PREFIX)) {
          const raw = sessionStorage.getItem(storageKey)
          if (raw === null) continue
          const key = storageKey.slice(SESSION_PREFIX.length)
          try {
            entries[key] = JSON.parse(raw)
          } catch {
            entries[key] = raw
          }
        }
      }
    } catch {
      // sessionStorage may be unavailable (private mode); best effort only
    }
    return entries
  },

  /**
   * Reconcile the mirror with the server's knowledge. Runs once per full page
   * load, from the first `connectParams()` call.
   *
   * Drops every mirrored key the server has acknowledged: the document GET
   * just re-read the storage backend, so for those keys its render is
   * authoritative and a mirror left over from an earlier page load (or made
   * stale by another tab writing the shared cookie) must not override it.
   *
   * Keeps exactly the keys the server has *not* acknowledged, i.e. the ones
   * still in the pending cookie. Note what this deliberately does NOT do: it
   * does not copy pending values *into* the mirror. The mirror is the
   * long-lived, opt-in carrier (`mirror: 'session'`), and a key that opted out
   * — `order` and `filters`, which round-trip through the URL — must not be
   * pinned across live navigation for the rest of the page load. Pending values
   * reach the socket directly from the cookie instead; see `connectParams()`.
   */
  prime () {
    const pending = readPending()

    try {
      const stale = []
      for (let i = 0; i < sessionStorage.length; i++) {
        const storageKey = sessionStorage.key(i)
        if (!storageKey || !storageKey.startsWith(SESSION_PREFIX)) continue
        if (!(storageKey.slice(SESSION_PREFIX.length) in pending)) stale.push(storageKey)
      }
      stale.forEach((storageKey) => sessionStorage.removeItem(storageKey))
    } catch {
      // sessionStorage may be unavailable (private mode); best effort only
    }
  },

  /**
   * LiveView connect params carrying this tab's mirrored preferences.
   *
   * Wire these into your LiveSocket with `backpexParams` (see the Backpex
   * installation guide) so they are re-evaluated on every join. The server
   * reads them in `mount/3`, *before* the first render — which is the whole
   * point: a LiveView's session snapshot is frozen at websocket-connect time,
   * so after a `live_redirect` re-mount it cannot see preference writes made
   * since. Handing the mirror over at join time lets the server render the
   * user's actual state instead of rendering stale state and correcting it a
   * frame later.
   *
   * Unacknowledged writes are merged in from the pending cookie and win over
   * the mirror, because they are by definition the most recent thing the user
   * did. This is what makes the connected render agree with the dead render on
   * the first join of a page load: the dead render honored those very writes
   * out of the same cookie, and a connected render that contradicted it *is*
   * the flash. Reading them from the cookie rather than from sessionStorage
   * also keeps the two carriers independent — a browser that allows cookies but
   * denies storage access still gets both renders right.
   *
   * @returns {{backpex_prefs: Object<string, any>}}
   */
  connectParams () {
    if (!this.connectParamsCalled) {
      this.connectParamsCalled = true
      this.prime()
    }

    return { backpex_prefs: { ...this.mirroredEntries(), ...readPending() } }
  },

  /**
   * Re-POST every write still marked pending. Runs once per page load, from
   * the hook's `mounted()` (which is also where `endpointPath` arrives).
   *
   * A keepalive POST that outlives its page never settles its promise, so the
   * write that lost the race against a reload can neither be confirmed nor
   * retried by the page that fired it — and its pending marker would otherwise
   * be sticky until `max-age` expires. The replay makes it durable and lets it
   * retire.
   */
  replayPending () {
    if (this.replayCalled) return
    this.replayCalled = true

    // One independent POST per key, rather than one batch. The controller's
    // batch form is best-effort, first-error-wins: it halts at the first entry
    // an adapter refuses and never dispatches the ones behind it. A batch replay
    // would nonetheless see a single completed response and retire all of them,
    // silently losing the writes the server never even looked at. Single writes
    // also give `:unidentified` its own `200 {ok: false}` per key instead of
    // failing the whole batch.
    //
    // `persist/3` re-marks each key pending (a no-op — it already is) and its
    // ack path retires it: the `_seq` guard keeps a key pending if a `set/3`
    // has raced this replay, and `clearPending/2` re-checks the value, so a
    // replay can never retire a newer write from this or any other tab.
    for (const [key, value] of Object.entries(readPending())) {
      this.persist(key, value, this._seq[key])
    }
  },

  /**
   * Persist a preference to the server immediately.
   * Uses keepalive to ensure request completes even during page navigation.
   *
   * Any *completed* response retires the pending entry — including
   * `200 {ok: false, reason: "unidentified"}` and `422`, which the preferences
   * controller returns for writes it refuses. The server has seen the write and
   * decided on it; replaying it would be pointless and keeping the client
   * overlay would pin the value forever. Only a request that never completed
   * (page unloaded mid-POST — the race this whole mechanism exists for — or a
   * network error) stays pending.
   *
   * @param {string} key
   * @param {any} value
   * @param {number} [seq] - the write's sequence number, from `set/3`.
   */
  persist (key, value, seq) {
    if (!this.endpointPath) {
      console.warn('BackpexPreferences: endpointPath not initialized')
      return
    }
    if (!this.csrfToken) {
      console.warn('BackpexPreferences: CSRF token not found')
      return
    }

    // Mark pending only once the request is actually going out. Marking in
    // set/3 instead would strand an entry in the cookie forever whenever these
    // guards fire (a mis-wired hook, a missing CSRF meta tag): nothing would
    // ever POST it, so nothing would ever retire it, and for the cookie's whole
    // lifetime the client would override the server on every dead render and
    // both sidebar hooks would refuse to adopt a corrected server attribute.
    // This is still synchronous and still precedes the fetch, so it keeps
    // beating a reload — which is the entire point of the cookie.
    markPending(key, value)

    // Use keepalive to ensure request survives page navigation
    fetch(this.endpointPath, {
      method: 'POST',
      keepalive: true,
      headers: {
        'Content-Type': 'application/json',
        'x-csrf-token': this.csrfToken
      },
      body: JSON.stringify({ key, value })
    })
      .then(() => {
        if (this._seq[key] === seq) clearPending(key, value)
      })
      .catch((error) => {
        // Leave the entry pending: the server never saw this write.
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
    BackpexPreferences.replayPending()

    this.handleEvent('backpex:set_preference', ({ key, value, mirror }) => {
      BackpexPreferences.set(key, value, { mirror })
    })

    // A join always evaluates the LiveSocket params before mounting hooks, so
    // reaching this point without connectParams() having run means the app's
    // LiveSocket is not wired up. Preferences written after connect would then
    // revert on the next live navigation.
    if (!BackpexPreferences.connectParamsCalled) {
      console.warn(
        'BackpexPreferences: LiveSocket params are not wired up. Pass `params: backpexParams({ _csrf_token: csrfToken })` ' +
        'to your LiveSocket so preferences survive live navigation. See the Backpex installation guide.'
      )
    }
  }
}

/**
 * Builds the LiveSocket `params` function Backpex needs.
 *
 * Must be a function (not a plain object) so LiveView re-evaluates it on every
 * join — including the joins that `live_redirect` performs — and picks up
 * preferences written since the page loaded.
 *
 * @param {Object<string, any>} [params] - your own connect params, e.g. `{ _csrf_token: csrfToken }`
 * @returns {function(): Object<string, any>}
 */
function backpexParams (params = {}) {
  return () => ({ ...params, ...BackpexPreferences.connectParams() })
}

export default BackpexPreferencesHook
export { BackpexPreferences, backpexParams }
