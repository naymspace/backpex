/**
 * Unified browser transport for Backpex preferences.
 *
 * Every configured adapter route receives an opaque server-signed namespace
 * token. Mirrored and pending values carry the token for their own key, so a
 * LiveView join may keep session-wide values while rejecting values belonging
 * to a narrower tenant/workspace namespace.
 */

const SESSION_PREFIX = 'backpex.prefs.'
const COOKIE_NAME = 'backpex_prefs'
const COOKIE_MAX_AGE = 300
const COOKIE_MAX_BYTES = 3072
const KEEPALIVE_MAX_BYTES = 60 * 1024
const WIRE_VERSION = 1
const HOOK_ELEMENT_ID = 'backpex-preferences'

function hookElement () {
  return document.getElementById(HOOK_ELEMENT_ID)
}

function currentEndpointPath () {
  return hookElement()?.dataset?.preferencesPath || null
}

function currentManifestRaw () {
  return hookElement()?.dataset?.preferencesManifest || null
}

function currentManifest () {
  const raw = currentManifestRaw()
  if (!raw) return null

  try {
    const manifest = JSON.parse(raw)
    if (manifest?.version !== WIRE_VERSION || !Array.isArray(manifest.routes)) return null
    return manifest
  } catch {
    return null
  }
}

function parseKey (key) {
  return key.includes(':') ? key.split(':') : key.split('.')
}

function startsWithSegments (segments, prefix) {
  return prefix.every((segment, index) => segments[index] === segment)
}

function routeMatches (route, key, segments) {
  if (route.kind === 'default') return true
  if (route.kind === 'exact') return route.pattern === key
  if (route.kind === 'wildcard') return startsWithSegments(segments, route.segments || [])
  return false
}

function compareRank (left = [], right = []) {
  for (let index = 0; index < Math.max(left.length, right.length); index++) {
    const difference = (left[index] || 0) - (right[index] || 0)
    if (difference !== 0) return difference
  }
  return 0
}

function routeForKey (key, manifest = currentManifest()) {
  if (!manifest || typeof key !== 'string') return null
  const segments = parseKey(key)

  return manifest.routes.reduce((best, route) => {
    if (!routeMatches(route, key, segments)) return best
    if (!best || compareRank(route.rank, best.rank) > 0) return route
    return best
  }, null)
}

function tokenForKey (key, manifest = currentManifest()) {
  return routeForKey(key, manifest)?.token || null
}

function storageKey (token, key) {
  return token ? `${SESSION_PREFIX}${token}.${key}` : null
}

function parseStorageKey (key) {
  if (!key?.startsWith(SESSION_PREFIX)) return null
  const rest = key.slice(SESSION_PREFIX.length)
  const separator = rest.indexOf('.')
  if (separator < 1) return null
  return { token: rest.slice(0, separator), key: rest.slice(separator + 1) }
}

function serialize (value) {
  if (typeof value === 'string') return value
  if (typeof value === 'boolean' || typeof value === 'number') return String(value)
  return JSON.stringify(value)
}

function deserialize (raw, fallback) {
  if (typeof fallback === 'boolean') return raw === 'true'
  if (typeof fallback === 'number') {
    const number = Number(raw)
    return Number.isNaN(number) ? fallback : number
  }
  if (typeof fallback === 'string') return raw

  try {
    return JSON.parse(raw)
  } catch {
    return fallback
  }
}

function readSession (key) {
  const token = tokenForKey(key)
  const keyName = storageKey(token, key)
  if (!keyName) return null

  try {
    return sessionStorage.getItem(keyName)
  } catch {
    return null
  }
}

function writeSession (key, value) {
  const token = tokenForKey(key)
  const keyName = storageKey(token, key)
  if (!keyName) return

  try {
    sessionStorage.setItem(keyName, value)
  } catch {
    // sessionStorage is best effort; the HTTP write remains authoritative.
  }
}

function storageEntries () {
  const entries = []

  try {
    for (let index = 0; index < sessionStorage.length; index++) {
      const storageName = sessionStorage.key(index)
      const parsed = parseStorageKey(storageName)
      if (!parsed) continue
      const raw = sessionStorage.getItem(storageName)
      if (raw !== null) entries.push({ ...parsed, storageName, raw })
    }
  } catch {
    return []
  }

  return entries
}

function pruneForeignMirrors () {
  const stale = storageEntries()
    .filter(({ key, token }) => tokenForKey(key) !== token)
    .map(({ storageName }) => storageName)

  try {
    stale.forEach((storageName) => sessionStorage.removeItem(storageName))
  } catch {
    // sessionStorage is best effort.
  }
}

function cookieAttributes (maxAge) {
  const secure = window.location.protocol === 'https:' ? '; Secure' : ''
  return `; path=/; max-age=${maxAge}; SameSite=Lax${secure}`
}

function readEnvelope () {
  const entry = document.cookie
    .split('; ')
    .find((cookie) => cookie.startsWith(`${COOKIE_NAME}=`))

  if (!entry) return null

  try {
    const decoded = JSON.parse(decodeURIComponent(entry.slice(COOKIE_NAME.length + 1)))
    if (decoded?.version !== WIRE_VERSION || typeof decoded.values !== 'object' || Array.isArray(decoded.values)) {
      return null
    }
    return decoded
  } catch {
    return null
  }
}

function validEntry (key, entry) {
  return entry && typeof entry === 'object' && !Array.isArray(entry) &&
    typeof entry.token === 'string' && entry.token === tokenForKey(key) &&
    Object.prototype.hasOwnProperty.call(entry, 'value')
}

function readPending () {
  const envelope = readEnvelope()
  if (!envelope) return {}

  return Object.fromEntries(
    Object.entries(envelope.values).filter(([key, entry]) => validEntry(key, entry))
  )
}

function writePendingMap (values) {
  const pending = { ...values }
  const encode = () => encodeURIComponent(JSON.stringify({ version: WIRE_VERSION, values: pending }))
  let encoded = encode()

  while (encoded.length > COOKIE_MAX_BYTES && Object.keys(pending).length > 1) {
    delete pending[Object.keys(pending)[0]]
    encoded = encode()
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
  } else {
    document.cookie = `${COOKIE_NAME}=${encoded}${cookieAttributes(COOKIE_MAX_AGE)}`
  }
}

function pruneForeignPending () {
  const envelope = readEnvelope()
  if (!envelope) {
    if (document.cookie.split('; ').some((cookie) => cookie.startsWith(`${COOKIE_NAME}=`))) {
      document.cookie = `${COOKIE_NAME}=${cookieAttributes(0)}`
    }
    return
  }

  writePendingMap(readPending())
}

function markPending (key, value) {
  const token = tokenForKey(key)
  if (!token) return null

  const pending = readPending()
  delete pending[key]
  pending[key] = { token, value }
  writePendingMap(pending)
  return token
}

function clearPending (key, value, token) {
  if (!token) return
  const envelope = readEnvelope()
  const entry = envelope?.values?.[key]
  if (!entry || entry.token !== token) return
  if (JSON.stringify(entry.value) !== JSON.stringify(value)) return

  const remaining = { ...envelope.values }
  delete remaining[key]
  writePendingMap(remaining)
}

function queueIdentity (endpointPath, token, key) {
  return JSON.stringify(token ? [token, key] : [endpointPath, key])
}

function requestBody (entries) {
  return JSON.stringify({
    preferences: entries.map(({ key, value }) => ({ key, value }))
  })
}

function byteLength (value) {
  return new TextEncoder().encode(value).byteLength
}

const BackpexPreferences = {
  endpointPath: null,
  manifest: null,
  scopeMarker: undefined,
  csrfToken: null,
  connectParamsCalled: false,
  replayCalled: false,
  primed: false,
  _seq: {},
  _queued: new Map(),
  _inFlight: null,
  _flushScheduled: false,

  init (endpointPath) {
    this.csrfToken = document.querySelector("meta[name='csrf-token']")?.content
    return this.syncScope(endpointPath)
  },

  // Kept as syncScope for the existing sidebar/theme hooks. The marker now
  // represents the adapter-route manifest only; endpoint changes are transport
  // changes and must not invalidate otherwise-compatible state.
  syncScope (endpointPath = currentEndpointPath()) {
    const raw = currentManifestRaw()
    const manifestChanged = this.scopeMarker !== raw
    const endpointChanged = this.endpointPath !== endpointPath

    this.endpointPath = endpointPath
    this.manifest = currentManifest()

    if (manifestChanged) {
      this.scopeMarker = raw
      pruneForeignMirrors()
      pruneForeignPending()
    }

    if (manifestChanged || endpointChanged) this.reconcileQueue(endpointPath)

    if (endpointChanged) this.replayCalled = false
    return manifestChanged
  },

  isPending (key) {
    return key in readPending()
  },

  get (key, fallback) {
    const raw = readSession(key)
    return raw === null ? fallback : deserialize(raw, fallback)
  },

  set (key, value, opts = {}) {
    this.syncScope()
    if (opts.mirror === 'session') writeSession(key, serialize(value))

    const seq = (this._seq[key] || 0) + 1
    this._seq[key] = seq
    this.persist(key, value, seq)
  },

  mirroredEntries () {
    const entries = {}

    for (const { key, token, raw } of storageEntries()) {
      if (tokenForKey(key) !== token) continue
      let value
      try {
        value = JSON.parse(raw)
      } catch {
        value = raw
      }
      entries[key] = { token, value }
    }

    return entries
  },

  // Runs once per full document load. The dead render has just read the
  // authoritative stores, so only still-pending mirrored values remain newer.
  prime () {
    const pending = readPending()
    const stale = storageEntries()
      .filter(({ key, token }) => tokenForKey(key) === token && !(key in pending))
      .map(({ storageName }) => storageName)

    try {
      stale.forEach((storageName) => sessionStorage.removeItem(storageName))
    } catch {
      // sessionStorage is best effort.
    }
  },

  connectParams () {
    this.connectParamsCalled = true
    this.syncScope()

    if (!this.primed) {
      this.prime()
      this.primed = true
    }

    return {
      backpex_prefs: {
        version: WIRE_VERSION,
        values: { ...this.mirroredEntries(), ...readPending() }
      }
    }
  },

  replayPending () {
    if (this.replayCalled) return
    this.replayCalled = true

    for (const [key, entry] of Object.entries(readPending())) {
      this.persist(key, entry.value, this._seq[key])
    }
  },

  persist (key, value, seq) {
    const endpointPath = currentEndpointPath()

    if (!endpointPath) {
      console.warn(
        `BackpexPreferences: dropping the write to ${key} because there is no #${HOOK_ELEMENT_ID} element on the ` +
        'page to read the preferences endpoint from. Backpex.HTML.Layout.app_shell/1 renders it; a custom layout ' +
        'must render <.preferences_root socket={@socket} preferences_manifest={@preferences_manifest} /> itself. ' +
        'See the Backpex user-preferences guide.'
      )
      return
    }
    if (!this.csrfToken) {
      console.warn('BackpexPreferences: CSRF token not found')
      return
    }

    const token = markPending(key, value)
    const identity = queueIdentity(endpointPath, token, key)

    // Coalesce writes that have not started yet. Once a request is in flight,
    // the next intent waits behind it so an older response can never overwrite
    // a newer value (or a sibling Session preference's cookie update).
    this._queued.delete(identity)
    this._queued.set(identity, { endpointPath, identity, key, seq, token, value })
    this.scheduleFlush()
  },

  reconcileQueue (endpointPath) {
    const compatible = new Map()

    for (const entry of this._queued.values()) {
      if (!entry.token || tokenForKey(entry.key) !== entry.token) continue
      const updated = {
        ...entry,
        endpointPath,
        identity: queueIdentity(endpointPath, entry.token, entry.key)
      }
      compatible.set(updated.identity, updated)
    }

    this._queued = compatible
  },

  scheduleFlush () {
    if (this._flushScheduled || this._inFlight || this._queued.size === 0) return
    this._flushScheduled = true

    queueMicrotask(() => {
      this._flushScheduled = false
      this.flush()
    })
  },

  flush () {
    if (this._inFlight || this._queued.size === 0) return

    const batch = this.nextBatch()
    this._inFlight = batch

    Promise.resolve()
      .then(() => fetch(batch.endpointPath, {
        method: 'POST',
        keepalive: batch.keepalive,
        headers: {
          'Content-Type': 'application/json',
          'x-csrf-token': this.csrfToken
        },
        body: batch.body
      }))
      .then((response) => this.handleResponse(response, batch))
      .catch((error) => {
        console.error('BackpexPreferences: failed to persist', error)
      })
      .finally(() => {
        this._inFlight = null
        this.scheduleFlush()
      })
  },

  nextBatch () {
    const first = this._queued.values().next().value
    const entries = []
    let body = null

    for (const entry of this._queued.values()) {
      if (entry.endpointPath !== first.endpointPath || entry.token !== first.token) continue

      const nextEntries = [...entries, entry]
      const nextBody = requestBody(nextEntries)

      if (entries.length > 0 && byteLength(nextBody) > KEEPALIVE_MAX_BYTES) break

      entries.push(entry)
      body = nextBody

      if (byteLength(body) > KEEPALIVE_MAX_BYTES) break
    }

    entries.forEach(({ identity }) => this._queued.delete(identity))

    return {
      body,
      endpointPath: first.endpointPath,
      entries,
      keepalive: byteLength(body) <= KEEPALIVE_MAX_BYTES
    }
  },

  async handleResponse (response, batch) {
    // 401/403 mean the session or CSRF token went stale (e.g. a re-login in
    // another tab), not that the writes are invalid — leave them pending so
    // the next full document load replays them with fresh credentials.
    if (response.status >= 500 || response.status === 401 || response.status === 403) {
      const keys = batch.entries.map(({ key }) => key).join(', ')
      console.error(
        `BackpexPreferences: error persisting ${keys} (HTTP ${response.status}); leaving them pending`
      )
      return
    }

    if (response.status === 422) {
      let body = null

      try {
        body = await response.json()
      } catch {
        // The built-in controller always returns JSON. Fall through to the
        // terminal acknowledgement used for malformed custom responses.
      }

      this.handleRejectedBatch(batch, body?.error?.key)
      return
    }

    batch.entries.forEach((entry) => this.acknowledge(entry))
  },

  handleRejectedBatch (batch, failedKey) {
    const failedEntry = batch.entries.find(({ key }) => key === failedKey)

    if (typeof failedKey !== 'string' || !failedEntry) {
      batch.entries.forEach((entry) => this.acknowledge(entry))
      return
    }

    const survivors = []

    for (const entry of batch.entries) {
      if (entry.key === failedKey) {
        this.acknowledge(entry)
      } else if (this.currentEntry(entry)) {
        const endpointPath = entry.token ? this.endpointPath : entry.endpointPath
        if (!endpointPath) continue

        const identity = queueIdentity(endpointPath, entry.token, entry.key)
        if (!this._queued.has(identity)) {
          survivors.push({ ...entry, endpointPath, identity })
        }
      }
    }

    // The controller stops at the first error and discards accumulated
    // Session effects. Retry every other still-current entry; eager adapters
    // are required to accept idempotent puts.
    this._queued = new Map([
      ...survivors.map((entry) => [entry.identity, entry]),
      ...this._queued
    ])
  },

  currentEntry (entry) {
    return this._seq[entry.key] === entry.seq && tokenForKey(entry.key) === entry.token
  },

  acknowledge (entry) {
    if (this.currentEntry(entry)) clearPending(entry.key, entry.value, entry.token)
  }
}

const BackpexPreferencesHook = {
  mounted () {
    BackpexPreferences.init(this.el.dataset.preferencesPath)
    BackpexPreferences.replayPending()

    this.handleEvent('backpex:set_preference', ({ key, value, mirror }) => {
      BackpexPreferences.set(key, value, { mirror })
    })

    if (!BackpexPreferences.connectParamsCalled) {
      console.warn(
        'BackpexPreferences: LiveSocket params are not wired up. Pass `params: backpexParams({ _csrf_token: csrfToken })` ' +
        'to your LiveSocket so preferences survive live navigation. See the Backpex installation guide.'
      )
    }
  },

  updated () {
    BackpexPreferences.init(this.el.dataset.preferencesPath)
    BackpexPreferences.replayPending()
  }
}

function backpexParams (params = {}) {
  return () => ({ ...params, ...BackpexPreferences.connectParams() })
}

export default BackpexPreferencesHook
export { BackpexPreferences, backpexParams }
