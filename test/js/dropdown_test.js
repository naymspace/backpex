import { afterEach, beforeEach, describe, expect, test } from 'bun:test'

import Dropdown from '../../assets/js/hooks/_dropdown'

class FakeElement {
  constructor (id, children = []) {
    const classes = new Set()

    this.id = id
    this.children = children
    this.listeners = {}
    this.classList = {
      add: (name) => classes.add(name),
      remove: (name) => classes.delete(name),
      contains: (name) => classes.has(name),
      toggle: (name, force) => {
        const add = force === undefined ? !classes.has(name) : force
        add ? classes.add(name) : classes.delete(name)
        return add
      }
    }
  }

  contains (node) {
    return node === this || this.children.some((child) => child.contains(node))
  }

  querySelector (selector) {
    const id = selector.slice(1)
    for (const child of this.children) {
      if (child.id === id) return child
      const found = child.querySelector(selector)
      if (found) return found
    }
    return null
  }

  addEventListener (type, listener) {
    this.listeners[type] = [...(this.listeners[type] || []), listener]
  }

  removeEventListener (type, listener) {
    this.listeners[type] = (this.listeners[type] || []).filter((l) => l !== listener)
  }

  dispatch (type, event) {
    for (const listener of this.listeners[type] || []) listener(event)
  }

  focus () {
    globalThis.document.activeElement = this
  }
}

function event (target, props = {}) {
  return { target, preventDefault: () => {}, ...props }
}

function editableDropdown () {
  const option = new FakeElement('option')
  const trigger = new FakeElement('dd-trigger')
  const menu = new FakeElement('dd-menu', [option])
  const root = new FakeElement('dd', [trigger, menu])
  return { root, trigger, menu, option }
}

function mountHook (root) {
  const hook = Object.create(Dropdown)
  hook.el = root
  hook.mounted()
  return hook
}

function patch (hook, children) {
  hook.beforeUpdate()
  hook.el.children = children
  hook.updated()
}

function isOpen (root) {
  return root.classList.contains('dropdown-open')
}

describe('BackpexDropdown', () => {
  beforeEach(() => {
    globalThis.document = new FakeElement('document')
    globalThis.document.activeElement = null
  })

  afterEach(() => {
    delete globalThis.document
  })

  test('toggles from the trigger and stays open for clicks in the menu', () => {
    const { root, trigger, option } = editableDropdown()
    mountHook(root)

    root.dispatch('mousedown', event(trigger))
    expect(isOpen(root)).toBe(true)

    root.dispatch('mousedown', event(option))
    expect(isOpen(root)).toBe(true)

    root.dispatch('mousedown', event(root))
    expect(isOpen(root)).toBe(false)
  })

  test('stays open for clicks in a menu that a patch re-created', () => {
    const { root } = editableDropdown()
    const hook = mountHook(root)

    // Before LiveView 1.2.10, a dropdown that turns readonly and back keeps
    // its hook, but the readonly render drops the menu, so it is re-created.
    const readonlyTrigger = new FakeElement('dd-trigger')
    patch(hook, [readonlyTrigger])

    const option = new FakeElement('option')
    const trigger = new FakeElement('dd-trigger')
    patch(hook, [trigger, new FakeElement('dd-menu', [option])])

    root.dispatch('mousedown', event(trigger))
    root.dispatch('mousedown', event(option))

    expect(isOpen(root)).toBe(true)
  })

  test('closes and does not open while a patch removed the menu', () => {
    const { root, trigger } = editableDropdown()
    const hook = mountHook(root)
    root.dispatch('mousedown', event(trigger))

    patch(hook, [trigger])
    expect(isOpen(root)).toBe(false)
    expect(document.listeners.mousedown).toEqual([])

    root.dispatch('mousedown', event(trigger))
    root.dispatch('keydown', event(trigger, { key: 'Enter' }))
    expect(isOpen(root)).toBe(false)
  })

  test('toggles with Enter and Space on the trigger only', () => {
    const { root, trigger, option } = editableDropdown()
    mountHook(root)

    root.dispatch('keydown', event(trigger, { key: 'Enter' }))
    expect(isOpen(root)).toBe(true)

    root.dispatch('keydown', event(option, { key: ' ' }))
    expect(isOpen(root)).toBe(true)

    root.dispatch('keydown', event(trigger, { key: ' ' }))
    expect(isOpen(root)).toBe(false)
  })

  test('focuses the current trigger on Escape after a patch replaced it', () => {
    const { root, trigger, menu } = editableDropdown()
    const hook = mountHook(root)
    root.dispatch('mousedown', event(trigger))

    const newTrigger = new FakeElement('dd-trigger')
    patch(hook, [newTrigger, menu])
    document.dispatch('keydown', event(document, { key: 'Escape' }))

    expect(isOpen(root)).toBe(false)
    expect(document.activeElement).toBe(newTrigger)
  })
})
