import { describe, expect, test } from 'bun:test'

import DragHover from '../../assets/js/hooks/_drag_hover'

function mountHook () {
  const entries = {}
  const classes = new Set()
  const hook = Object.create(DragHover)

  hook.el = {
    firstElementChild: {
      classList: {
        toggle: (name, force) => {
          force ? classes.add(name) : classes.delete(name)
          return force
        }
      }
    },
    addEventListener (type, listener, options = {}) {
      const entry = { listener, active: true }
      entries[type] = [...(entries[type] || []), entry]
      options.signal?.addEventListener('abort', () => { entry.active = false })
    }
  }
  hook.mounted()

  const dispatch = (type) => {
    for (const entry of entries[type] || []) {
      if (entry.active) entry.listener()
    }
  }
  const activeListeners = () => Object.values(entries).flat().filter((entry) => entry.active).length

  return { hook, classes, dispatch, activeListeners }
}

describe('BackpexDragHover', () => {
  test('highlights the dropzone on dragenter and clears it on dragleave', () => {
    const { classes, dispatch } = mountHook()

    dispatch('dragenter')
    expect(classes.has('border-primary')).toBe(true)

    dispatch('dragleave')
    expect(classes.has('border-primary')).toBe(false)
  })

  test('stays highlighted until the pointer left every nested element', () => {
    const { classes, dispatch } = mountHook()

    // Entering a child fires dragenter on the child before dragleave on the parent.
    dispatch('dragenter')
    dispatch('dragenter')
    dispatch('dragleave')
    expect(classes.has('border-primary')).toBe(true)

    dispatch('dragleave')
    expect(classes.has('border-primary')).toBe(false)
  })

  test('clears the highlight and resets the counter on drop', () => {
    const { hook, classes, dispatch } = mountHook()

    dispatch('dragenter')
    dispatch('dragenter')
    dispatch('drop')

    expect(classes.has('border-primary')).toBe(false)
    expect(hook.dragging).toBe(0)
  })

  test('does not react to dragover', () => {
    const { classes, dispatch } = mountHook()

    dispatch('dragover')

    expect(classes.has('border-primary')).toBe(false)
  })

  test('removes its listeners on destroy', () => {
    const { hook, classes, dispatch, activeListeners } = mountHook()

    expect(activeListeners()).toBe(3)

    hook.destroyed()
    dispatch('dragenter')

    expect(activeListeners()).toBe(0)
    expect(classes.has('border-primary')).toBe(false)
  })
})
