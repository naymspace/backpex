import { afterEach, beforeEach, describe, expect, test } from 'bun:test'

import Tooltip from '../../assets/js/hooks/_tooltip'

// Minimal event target that honours the `signal` option of addEventListener.
function eventTarget () {
  const listeners = {}

  return {
    addEventListener (type, listener, options = {}) {
      const entry = { listener, active: true }
      listeners[type] = [...(listeners[type] || []), entry]
      options.signal?.addEventListener('abort', () => { entry.active = false })
    },
    dispatch (type) {
      for (const entry of listeners[type] || []) {
        if (entry.active) entry.listener()
      }
    },
    activeCount (type) {
      return (listeners[type] || []).filter((entry) => entry.active).length
    }
  }
}

function fakeTooltipElement () {
  return {
    innerText: '',
    className: '',
    style: {},
    offsetHeight: 20,
    removed: false,
    remove () { this.removed = true }
  }
}

function fakeHookElement (text) {
  return Object.assign(eventTarget(), {
    rect: { left: 100, top: 200, width: 40 },
    getAttribute: (name) => (name === 'data-tooltip' ? text : null),
    getBoundingClientRect () { return this.rect }
  })
}

function mountHook (el) {
  const hook = Object.create(Tooltip)
  hook.el = el
  hook.mounted()
  return hook
}

describe('BackpexTooltip', () => {
  let appended
  let win

  beforeEach(() => {
    appended = []
    win = eventTarget()
    globalThis.window = win
    globalThis.document = {
      createElement: () => fakeTooltipElement(),
      body: { appendChild: (node) => appended.push(node) }
    }
  })

  afterEach(() => {
    delete globalThis.window
    delete globalThis.document
  })

  test('shows a tooltip with the data-tooltip text above the element on mouseenter', () => {
    const el = fakeHookElement('Delete')
    mountHook(el)

    el.dispatch('mouseenter')

    expect(appended).toHaveLength(1)
    expect(appended[0].innerText).toBe('Delete')
    expect(appended[0].className).toContain('fixed')
    // centered horizontally: left + width / 2; above: top - tooltip height - 6
    expect(appended[0].style.left).toBe('120px')
    expect(appended[0].style.top).toBe('174px')
  })

  test('does not show a tooltip without text', () => {
    const el = fakeHookElement(null)
    mountHook(el)

    el.dispatch('mouseenter')

    expect(appended).toHaveLength(0)
  })

  test('removes the tooltip on mouseleave and on click', () => {
    for (const event of ['mouseleave', 'click']) {
      appended = []
      const el = fakeHookElement('Edit')
      const hook = mountHook(el)

      el.dispatch('mouseenter')
      const tooltip = appended[0]
      el.dispatch(event)

      expect(tooltip.removed).toBe(true)
      expect(hook.tooltip).toBeNull()
    }
  })

  test('keeps the tooltip above the element while the page scrolls', () => {
    const el = fakeHookElement('Edit')
    mountHook(el)
    el.dispatch('mouseenter')

    el.rect = { left: 100, top: 100, width: 40 }
    win.dispatch('scroll')

    expect(appended[0].style.left).toBe('120px')
    expect(appended[0].style.top).toBe('74px')
  })

  test('ignores scroll while no tooltip is shown', () => {
    const el = fakeHookElement('Edit')
    mountHook(el)

    win.dispatch('scroll')

    expect(appended).toHaveLength(0)
  })

  test('removes the tooltip and all listeners on destroy', () => {
    const el = fakeHookElement('Edit')
    const hook = mountHook(el)
    el.dispatch('mouseenter')
    const tooltip = appended[0]

    expect(win.activeCount('scroll')).toBe(1)

    hook.destroyed()

    expect(tooltip.removed).toBe(true)
    expect(hook.tooltip).toBeNull()
    expect(win.activeCount('scroll')).toBe(0)
    expect(el.activeCount('mouseenter')).toBe(0)
    expect(el.activeCount('mouseleave')).toBe(0)
    expect(el.activeCount('click')).toBe(0)

    el.dispatch('mouseenter')
    expect(appended).toHaveLength(1)
  })
})
