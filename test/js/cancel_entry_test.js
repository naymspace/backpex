import { describe, expect, test } from 'bun:test'

import CancelEntry from '../../assets/js/hooks/_cancel_entry'

function mountHook ({ form }) {
  const handlers = {}
  const dispatched = []
  const hook = Object.create(CancelEntry)

  hook.el = {
    dataset: { uploadKey: 'avatar' },
    closest: (selector) => (selector === 'form' ? form : null),
    dispatchEvent: (event) => dispatched.push(event)
  }
  hook.handleEvent = (name, callback) => { handlers[name] = callback }
  hook.mounted()

  return { handlers, dispatched }
}

describe('BackpexCancelEntry', () => {
  test('listens to the cancel events of its own upload key only', () => {
    const { handlers } = mountHook({ form: {} })

    expect(Object.keys(handlers).sort()).toEqual(['cancel-entry:avatar', 'cancel-existing-entry:avatar'])
  })

  test('dispatches a bubbling input event when an entry is cancelled', () => {
    const { handlers, dispatched } = mountHook({ form: {} })

    handlers['cancel-entry:avatar']({})

    expect(dispatched).toHaveLength(1)
    expect(dispatched[0].type).toBe('input')
    expect(dispatched[0].bubbles).toBe(true)
  })

  test('dispatches a bubbling input event when an existing entry is cancelled', () => {
    const { handlers, dispatched } = mountHook({ form: {} })

    handlers['cancel-existing-entry:avatar']({})

    expect(dispatched).toHaveLength(1)
    expect(dispatched[0].type).toBe('input')
    expect(dispatched[0].bubbles).toBe(true)
  })

  test('dispatches nothing when the element is not inside a form', () => {
    const { handlers, dispatched } = mountHook({ form: null })

    handlers['cancel-entry:avatar']({})
    handlers['cancel-existing-entry:avatar']({})

    expect(dispatched).toHaveLength(0)
  })
})
