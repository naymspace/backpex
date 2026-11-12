import { afterEach, beforeEach, describe, expect, test } from 'bun:test'

import Combobox, {
  computePopupPosition,
  matchesQuery,
  nextEnabledIndex,
  normalizeText,
  typeaheadIndex
} from '../../assets/js/hooks/_combobox'

describe('normalizeText and matchesQuery', () => {
  test('ignore case and diacritics', () => {
    expect(normalizeText('Zürich')).toBe('zurich')
    expect(normalizeText('ÉCOLE Ångström')).toBe('ecole angstrom')
    // Decomposed input (e + combining acute) normalizes the same as composed.
    expect(normalizeText('René')).toBe('rene')
    expect(normalizeText(null)).toBe('')
    expect(normalizeText(42)).toBe('42')

    expect(matchesQuery('René Descartes', 'rene')).toBe(true)
    expect(matchesQuery('Rene Descartes', 'RENÉ')).toBe(true)
    expect(matchesQuery('Zürich', 'ZUR')).toBe(true)
  })

  test('match substrings and treat a blank query as a match', () => {
    expect(matchesQuery('Strawberry', 'berr')).toBe(true)
    expect(matchesQuery('Strawberry', 'cherry')).toBe(false)
    expect(matchesQuery('Strawberry', '')).toBe(true)
    expect(matchesQuery('Strawberry', '   ')).toBe(true)
    expect(matchesQuery('Straw berry', 'w b')).toBe(true)
  })

  test('keep letters that are not a base letter plus diacritic', () => {
    // ß and ø do not decompose; they must stay searchable as themselves.
    expect(matchesQuery('Straße', 'straß')).toBe(true)
    expect(matchesQuery('København', 'københ')).toBe(true)
  })
})

describe('nextEnabledIndex', () => {
  const enabled = [false, true, true, false, true, false]

  test('moves to the next and previous enabled index, skipping disabled ones', () => {
    expect(nextEnabledIndex(enabled, 1, 'next')).toBe(2)
    expect(nextEnabledIndex(enabled, 2, 'next')).toBe(4)
    expect(nextEnabledIndex(enabled, 4, 'previous')).toBe(2)
    expect(nextEnabledIndex(enabled, 2, 'previous')).toBe(1)
  })

  test('does not wrap at either end', () => {
    expect(nextEnabledIndex(enabled, 4, 'next')).toBe(4)
    expect(nextEnabledIndex(enabled, 1, 'previous')).toBe(1)
  })

  test('starts at the first or last without a current index', () => {
    expect(nextEnabledIndex(enabled, -1, 'next')).toBe(1)
    expect(nextEnabledIndex(enabled, -1, 'previous')).toBe(4)
  })

  test('leaves a current index that became disabled towards the nearest enabled one', () => {
    expect(nextEnabledIndex(enabled, 3, 'next')).toBe(4)
    expect(nextEnabledIndex(enabled, 3, 'previous')).toBe(2)
    expect(nextEnabledIndex(enabled, 5, 'next')).toBe(4)
    expect(nextEnabledIndex(enabled, 0, 'previous')).toBe(1)
  })

  test('jumps to the first and last enabled index', () => {
    expect(nextEnabledIndex(enabled, 2, 'first')).toBe(1)
    expect(nextEnabledIndex(enabled, 2, 'last')).toBe(4)
  })

  test('returns -1 when nothing is enabled', () => {
    for (const direction of ['next', 'previous', 'first', 'last']) {
      expect(nextEnabledIndex([false, false], 0, direction)).toBe(-1)
      expect(nextEnabledIndex([], -1, direction)).toBe(-1)
    }
  })
})

describe('typeaheadIndex', () => {
  const labels = ['Low', 'Medium', 'High', 'Highest', 'Urgent', 'Hold']
  const enabled = [true, true, true, true, true, true]

  test('finds the first label starting with the buffer, ignoring case and diacritics', () => {
    expect(typeaheadIndex(labels, enabled, 'h', -1)).toBe(2)
    expect(typeaheadIndex(labels, enabled, 'M', -1)).toBe(1)
    expect(typeaheadIndex(['Émile', 'Eva'], [true, true], 'em', -1)).toBe(0)
  })

  test('refines the current match with a longer buffer', () => {
    expect(typeaheadIndex(labels, enabled, 'hi', 2)).toBe(2)
    expect(typeaheadIndex(labels, enabled, 'highe', 2)).toBe(3)
    expect(typeaheadIndex(labels, enabled, 'ho', 2)).toBe(5)
  })

  test('cycles through the labels of a repeated character, wrapping around', () => {
    expect(typeaheadIndex(labels, enabled, 'hh', 2)).toBe(3)
    expect(typeaheadIndex(labels, enabled, 'hhh', 3)).toBe(5)
    expect(typeaheadIndex(labels, enabled, 'hhhh', 5)).toBe(2)
  })

  test('skips disabled options and returns -1 without a match', () => {
    expect(typeaheadIndex(labels, [true, true, false, true, true, true], 'h', -1)).toBe(3)
    expect(typeaheadIndex(labels, enabled, 'x', -1)).toBe(-1)
    expect(typeaheadIndex(labels, enabled, '', 0)).toBe(-1)
    expect(typeaheadIndex(labels, enabled.map(() => false), 'h', -1)).toBe(-1)
  })
})

describe('computePopupPosition', () => {
  const viewport = { width: 1000, height: 800 }
  const anchor = (top, left = 100, width = 300, height = 40) => ({ top, bottom: top + height, left, width })

  test('opens below the control when the popup fits', () => {
    const position = computePopupPosition({ anchor: anchor(100), popup: { width: 200, height: 300 }, viewport })

    expect(position).toEqual({
      placement: 'bottom',
      top: 144,
      left: 100,
      minWidth: 300,
      maxWidth: 984,
      maxHeight: 800 - 140 - 4 - 8
    })
  })

  test('flips above when there is not enough room below and more above', () => {
    const position = computePopupPosition({ anchor: anchor(600), popup: { width: 300, height: 300 }, viewport })

    expect(position.placement).toBe('top')
    expect(position.maxHeight).toBe(600 - 4 - 8)
    // The bottom of the popup sits the offset above the control.
    expect(position.top + 300).toBe(600 - 4)
  })

  test('stays below when it does not fit on either side but below has more room', () => {
    const position = computePopupPosition({ anchor: anchor(300), popup: { width: 300, height: 900 }, viewport })

    expect(position.placement).toBe('bottom')
    expect(position.maxHeight).toBe(800 - 340 - 4 - 8)
    expect(position.top).toBe(344)
  })

  test('limits a popup flipped above to the room above', () => {
    const position = computePopupPosition({ anchor: anchor(500), popup: { width: 300, height: 900 }, viewport })

    expect(position.placement).toBe('top')
    expect(position.maxHeight).toBe(488)
    expect(position.top).toBe(8)
  })

  test('keeps the popup inside the viewport horizontally', () => {
    const right = computePopupPosition({ anchor: anchor(100, 900, 80), popup: { width: 300, height: 100 }, viewport })
    expect(right.left).toBe(1000 - 8 - 300)

    const left = computePopupPosition({ anchor: anchor(100, -50, 200), popup: { width: 200, height: 100 }, viewport })
    expect(left.left).toBe(8)
  })

  test('is at least as wide as the control but never wider than the viewport', () => {
    const narrow = { width: 360, height: 640 }
    const position = computePopupPosition({ anchor: anchor(100, 16, 328), popup: { width: 600, height: 100 }, viewport: narrow })

    expect(position.minWidth).toBe(328)
    expect(position.maxWidth).toBe(344)
    expect(position.left).toBe(8)

    const wideControl = computePopupPosition({ anchor: anchor(100, 0, 500), popup: { width: 100, height: 100 }, viewport: narrow })
    expect(wideControl.minWidth).toBe(344)
  })

  test('never reports a negative maximum height for a control outside the viewport', () => {
    const below = computePopupPosition({ anchor: anchor(900), popup: { width: 100, height: 100 }, viewport })
    expect(below.maxHeight).toBeGreaterThanOrEqual(0)

    const above = computePopupPosition({ anchor: anchor(-200), popup: { width: 100, height: 100 }, viewport })
    expect(above.placement).toBe('bottom')
    expect(above.maxHeight).toBeGreaterThanOrEqual(0)
  })
})

// The hook's DOM behaviour is covered by the browser tests. These cover what a
// browser test cannot observe deterministically: timers and the order in which
// search replies arrive.
describe('BackpexCombobox server search', () => {
  class FakeRoot {
    constructor (attributes) {
      this.id = 'person'
      this.attributes = new Map(Object.entries(attributes))
      this.dataset = { onSearch: 'search', searchDebounce: '100' }
      this.listeners = []
    }

    getAttribute (name) { return this.attributes.get(name) ?? null }
    hasAttribute (name) { return this.attributes.has(name) }
    toggleAttribute (name, force) {
      force ? this.attributes.set(name, '') : this.attributes.delete(name)
      return force
    }

    querySelector () { return null }
    querySelectorAll () { return [] }
    addEventListener (type, listener, { signal }) {
      const entry = { type, listener }
      this.listeners.push(entry)
      signal.addEventListener('abort', () => { this.listeners = this.listeners.filter((e) => e !== entry) })
    }
  }

  let realSetTimeout, realClearTimeout, timers

  beforeEach(() => {
    timers = new Map()
    let next = 1
    realSetTimeout = globalThis.setTimeout
    realClearTimeout = globalThis.clearTimeout
    globalThis.setTimeout = (fun) => { const id = next++; timers.set(id, fun); return id }
    globalThis.clearTimeout = (id) => timers.delete(id)
  })

  afterEach(() => {
    globalThis.setTimeout = realSetTimeout
    globalThis.clearTimeout = realClearTimeout
  })

  function runTimers () {
    const pending = [...timers.values()]
    timers.clear()
    for (const fun of pending) fun()
  }

  function mountHook (attributes = { 'data-on-search': 'search' }) {
    const hook = Object.create(Combobox)
    hook.el = new FakeRoot(attributes)
    hook.pushes = []
    hook.pushEvent = (event, payload) => {
      return new Promise((resolve) => hook.pushes.push({ event, payload, resolve }))
    }
    hook.pushEventTo = (target, event, payload) => {
      hook.pushes.push({ target, event, payload, resolve: () => {} })
      return Promise.resolve([])
    }
    hook.mounted()
    return hook
  }

  test('pushes only the last query after the debounce', () => {
    const hook = mountHook()
    hook.search('a')
    hook.search('ad')
    expect(hook.pushes).toEqual([])

    runTimers()
    expect(hook.pushes.map((push) => push.payload)).toEqual([{ query: 'ad', id: 'person' }])
  })

  test('pushes to phx-target when the root has one', () => {
    const hook = mountHook({ 'data-on-search': 'search', 'phx-target': '3' })
    hook.search('ad')
    runTimers()

    expect(hook.pushes).toMatchObject([{ target: '3', event: 'search', payload: { query: 'ad', id: 'person' } }])
  })

  test('a late reply to an older query keeps the loading state of a newer one', async () => {
    const hook = mountHook()
    hook.search('a')
    runTimers()
    hook.search('ad')
    runTimers()
    expect(hook.el.hasAttribute('data-loading')).toBe(true)

    hook.pushes[0].resolve()
    await Promise.resolve()
    await Promise.resolve()
    expect(hook.el.hasAttribute('data-loading')).toBe(true)

    hook.pushes[1].resolve()
    await Promise.resolve()
    await Promise.resolve()
    expect(hook.el.hasAttribute('data-loading')).toBe(false)
  })

  test('destroyed() removes the document and window listeners of an open popup', () => {
    const target = () => ({
      listeners: [],
      addEventListener (type, listener, { signal }) {
        const entry = { type }
        this.listeners.push(entry)
        signal.addEventListener('abort', () => { this.listeners = this.listeners.filter((e) => e !== entry) })
      }
    })
    const realDocument = globalThis.document
    const realWindow = globalThis.window
    globalThis.document = target()
    globalThis.window = target()

    try {
      const hook = mountHook()
      hook.attachOpenListeners()
      expect(document.listeners.map((l) => l.type)).toEqual(['pointerdown', 'scroll'])
      expect(window.listeners.map((l) => l.type)).toEqual(['resize'])

      hook.destroyed()
      expect(document.listeners).toEqual([])
      expect(window.listeners).toEqual([])
    } finally {
      globalThis.document = realDocument
      globalThis.window = realWindow
    }
  })

  test('destroyed() cancels a pending search and removes the listeners', () => {
    const hook = mountHook()
    expect(hook.el.listeners.length).toBeGreaterThan(0)

    hook.search('ad')
    hook.destroyed()
    runTimers()

    expect(hook.pushes).toEqual([])
    expect(hook.el.listeners).toEqual([])
  })
})
