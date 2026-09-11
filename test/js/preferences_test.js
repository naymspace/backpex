import { afterEach, beforeEach, describe, expect, mock, spyOn, test } from 'bun:test'

import { BackpexPreferences } from '../../assets/js/hooks/_preferences'

const manifest = JSON.stringify({
  version: 1,
  routes: [{ kind: 'default', token: 'session-token' }]
})

function installBrowserGlobals () {
  const cookies = new Map()

  globalThis.document = {
    getElementById: () => ({
      dataset: {
        preferencesManifest: manifest,
        preferencesPath: '/backpex_preferences'
      }
    }),
    querySelector: () => ({ content: 'csrf-token' })
  }

  Object.defineProperty(globalThis.document, 'cookie', {
    configurable: true,
    get: () => [...cookies].map(([key, value]) => `${key}=${value}`).join('; '),
    set: (raw) => {
      const [pair, ...attributes] = raw.split(';')
      const separator = pair.indexOf('=')
      const key = pair.slice(0, separator)
      const value = pair.slice(separator + 1)
      const expired = attributes.some((attribute) => attribute.trim().toLowerCase() === 'max-age=0')

      if (expired) {
        cookies.delete(key)
      } else {
        cookies.set(key, value)
      }
    }
  })

  globalThis.window = { location: { protocol: 'http:' } }
  globalThis.sessionStorage = {
    getItem: () => null,
    key: () => null,
    length: 0,
    removeItem: () => {},
    setItem: () => {}
  }
}

function resetPreferences () {
  BackpexPreferences.endpointPath = null
  BackpexPreferences.manifest = null
  BackpexPreferences.scopeMarker = undefined
  BackpexPreferences.csrfToken = null
  BackpexPreferences.connectParamsCalled = false
  BackpexPreferences.replayCalled = false
  BackpexPreferences.primed = false
  BackpexPreferences._seq = {}
  BackpexPreferences._queued = new Map()
  BackpexPreferences._inFlight = null
  BackpexPreferences._flushScheduled = false
}

async function waitFor (predicate) {
  for (let attempt = 0; attempt < 50; attempt++) {
    if (predicate()) return
    await new Promise((resolve) => setTimeout(resolve, 0))
  }

  throw new Error('Timed out waiting for preference transport')
}

function pendingValues () {
  const entry = document.cookie
    .split('; ')
    .find((cookie) => cookie.startsWith('backpex_prefs='))

  if (!entry) return {}

  return JSON.parse(decodeURIComponent(entry.split('=', 2)[1])).values
}

function jsonResponse (body, options = {}) {
  return {
    headers: { get: () => options.contentType || 'application/json; charset=utf-8' },
    json: async () => body,
    redirected: options.redirected || false,
    status: options.status || 200
  }
}

function plainResponse (status, options = {}) {
  return {
    headers: { get: () => options.contentType || 'text/html; charset=utf-8' },
    json: async () => { throw new Error('not JSON') },
    redirected: options.redirected || false,
    status
  }
}

describe('BackpexPreferences pending cookie', () => {
  let requests
  let persisted
  let error
  let warn

  beforeEach(() => {
    installBrowserGlobals()
    resetPreferences()
    requests = []
    persisted = new Map()
    error = spyOn(console, 'error').mockImplementation(() => {})
    warn = spyOn(console, 'warn').mockImplementation(() => {})

    globalThis.fetch = mock((_path, options) => new Promise((resolve) => {
      requests.push({ body: JSON.parse(options.body), resolve })
    }))

    BackpexPreferences.init('/backpex_preferences')
  })

  afterEach(() => {
    error.mockRestore()
    warn.mockRestore()
    delete globalThis.document
    delete globalThis.fetch
    delete globalThis.sessionStorage
    delete globalThis.window
  })

  test('does not replay an older value when its replacement exceeds the cookie budget', async () => {
    const oversizedValue = 'x'.repeat(4000)

    BackpexPreferences.set('custom.big', 'old')
    await waitFor(() => requests.length === 1)

    BackpexPreferences.set('custom.keep', 'pending sibling')
    BackpexPreferences.set('custom.big', oversizedValue)

    expect(warn).toHaveBeenCalledTimes(1)
    expect(pendingValues()).toEqual({
      'custom.keep': { token: 'session-token', value: 'pending sibling' }
    })

    const succeed = (request) => {
      request.body.preferences.forEach(({ key, value }) => persisted.set(key, value))
      request.resolve(jsonResponse({ ok: true }))
    }

    succeed(requests[0])
    await waitFor(() => requests.length === 2)
    succeed(requests[1])
    await waitFor(() => BackpexPreferences._inFlight === null)

    expect(persisted.get('custom.big')).toBe(oversizedValue)
    expect(persisted.get('custom.keep')).toBe('pending sibling')
    expect(document.cookie).not.toContain('backpex_prefs=')

    resetPreferences()
    BackpexPreferences.init('/backpex_preferences')

    expect(BackpexPreferences.connectParams().backpex_prefs.values).toEqual({})
    BackpexPreferences.replayPending()
    await new Promise((resolve) => setTimeout(resolve, 0))
    expect(requests).toHaveLength(2)
  })

  test('acknowledges a verified JSON success response', async () => {
    BackpexPreferences.set('custom.theme', 'dark')
    await waitFor(() => requests.length === 1)

    expect(pendingValues()['custom.theme'].value).toBe('dark')
    requests[0].resolve(jsonResponse({ ok: true }))
    await waitFor(() => BackpexPreferences._inFlight === null)

    expect(document.cookie).not.toContain('backpex_prefs=')
    expect(error).not.toHaveBeenCalled()
  })

  test('leaves a followed login redirect pending', async () => {
    BackpexPreferences.set('custom.theme', 'dark')
    await waitFor(() => requests.length === 1)

    requests[0].resolve(plainResponse(200, { redirected: true }))
    await waitFor(() => BackpexPreferences._inFlight === null)

    expect(pendingValues()['custom.theme'].value).toBe('dark')
    expect(error).toHaveBeenCalledWith(
      'BackpexPreferences: error persisting custom.theme (redirected response); leaving them pending'
    )
  })

  test('leaves a rate-limited response pending', async () => {
    BackpexPreferences.set('custom.theme', 'dark')
    await waitFor(() => requests.length === 1)

    requests[0].resolve(jsonResponse({ ok: false }, { status: 429 }))
    await waitFor(() => BackpexPreferences._inFlight === null)

    expect(pendingValues()['custom.theme'].value).toBe('dark')
    expect(error).toHaveBeenCalledWith(
      'BackpexPreferences: error persisting custom.theme (HTTP 429); leaving them pending'
    )
  })

  test('leaves a non-JSON 200 response pending', async () => {
    BackpexPreferences.set('custom.theme', 'dark')
    await waitFor(() => requests.length === 1)

    requests[0].resolve(plainResponse(200))
    await waitFor(() => BackpexPreferences._inFlight === null)

    expect(pendingValues()['custom.theme'].value).toBe('dark')
    expect(error).toHaveBeenCalledWith(
      'BackpexPreferences: error persisting custom.theme (HTTP 200); leaving them pending'
    )
  })

  test('retires an explicit terminal JSON no-op', async () => {
    BackpexPreferences.set('custom.noop', 'value')
    await waitFor(() => requests.length === 1)

    requests[0].resolve(jsonResponse({
      ok: false,
      error: { key: 'custom.noop', reason: 'unscoped' }
    }))
    await waitFor(() => BackpexPreferences._inFlight === null)

    expect(document.cookie).not.toContain('backpex_prefs=')
    expect(error).not.toHaveBeenCalled()
  })

  test('keeps the existing 422 partial-batch retry behavior', async () => {
    BackpexPreferences.set('custom.rejected', 'invalid')
    BackpexPreferences.set('custom.survivor', 'valid')
    await waitFor(() => requests.length === 1)

    requests[0].resolve(jsonResponse(
      { ok: false, error: { key: 'custom.rejected', reason: 'invalid_value' } },
      { status: 422 }
    ))
    await waitFor(() => requests.length === 2)

    expect(requests[1].body.preferences).toEqual([
      { key: 'custom.survivor', value: 'valid' }
    ])
    expect(pendingValues()).toEqual({
      'custom.survivor': { token: 'session-token', value: 'valid' }
    })

    requests[1].resolve(jsonResponse({ ok: true }))
    await waitFor(() => BackpexPreferences._inFlight === null)

    expect(document.cookie).not.toContain('backpex_prefs=')
  })
})
