import { afterEach, beforeEach, describe, expect, test } from 'bun:test'

import StickyActions from '../../assets/js/hooks/_sticky_actions'

function cell () {
  const attributes = new Set()

  return {
    hasAttribute: (name) => attributes.has(name),
    toggleAttribute: (name, force) => {
      const add = force === undefined ? !attributes.has(name) : force
      add ? attributes.add(name) : attributes.delete(name)
      return add
    }
  }
}

function mountHook (row) {
  const hook = Object.create(StickyActions)
  hook.el = row
  hook.mounted()
  return hook
}

describe('BackpexStickyActions', () => {
  let observers
  let row
  let sticky

  beforeEach(() => {
    observers = []

    globalThis.IntersectionObserver = class {
      constructor (callback) {
        this.callback = callback
        this.disconnected = false
        observers.push(this)
      }

      observe (el) { this.target = el }
      disconnect () { this.disconnected = true }
      intersect (intersectionRatio) { this.callback([{ intersectionRatio }]) }
    }

    sticky = cell()
    row = { closest: () => null, querySelector: () => sticky }
  })

  afterEach(() => {
    delete globalThis.IntersectionObserver
  })

  test('marks the sticky cell as stuck when the row overflows', () => {
    const hook = mountHook(row)

    observers[0].intersect(0.5)
    expect(sticky.hasAttribute('stuck')).toBe(true)

    observers[0].intersect(1)
    expect(sticky.hasAttribute('stuck')).toBe(false)

    hook.destroyed()
    expect(observers[0].disconnected).toBe(true)
  })

  test('marks the current sticky cell after a patch replaced it', () => {
    const hook = mountHook(row)
    observers[0].intersect(0.5)

    // Toggling a column makes LiveView morph a different cell into the sticky one.
    const newSticky = cell()
    row.querySelector = () => newSticky
    hook.updated()

    expect(newSticky.hasAttribute('stuck')).toBe(true)
  })

  test('does not mark the sticky cell before the observer reported', () => {
    const hook = mountHook(row)

    hook.updated()

    expect(sticky.hasAttribute('stuck')).toBe(false)
  })
})
