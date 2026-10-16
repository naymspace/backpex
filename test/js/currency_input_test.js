import { describe, expect, mock, test } from 'bun:test'

const masks = []

mock.module('imask', () => ({
  default: (element, options) => {
    const mask = {
      element,
      options,
      listeners: {},
      unmaskedValue: '',
      value: '',
      on (event, handler) {
        this.listeners[event] = [...(this.listeners[event] || []), handler]
      },
      destroy () {}
    }

    masks.push(mask)
    return mask
  }
}))

const { default: CurrencyInput } = await import('../../assets/js/hooks/_currency_input')

function mountHook ({ thousandsSeparator, radix = '.', unit = '$', value = '' }) {
  const maskedInput = {}
  const hiddenInput = { value }
  const dataset = { maskPattern: '$num', radix, unit }

  if (thousandsSeparator !== undefined) dataset.thousandsSeparator = thousandsSeparator

  const hook = Object.create(CurrencyInput)
  hook.el = {
    dataset,
    querySelector: (selector) => (selector === '[data-masked-input]' ? maskedInput : hiddenInput)
  }

  return hook
}

describe('BackpexCurrencyInput', () => {
  const cases = [
    { name: 'an empty separator', thousandsSeparator: '', masked: '$1234567.89', raw: '1234567.89' },
    { name: 'a comma', thousandsSeparator: ',', masked: '$1,234,567.89', raw: '1234567.89' },
    // The radix stays in the raw value; the server (e.g. the Money library) parses it.
    { name: 'a dot', thousandsSeparator: '.', radix: ',', masked: '$1.234.567,89', raw: '1234567,89' },
    { name: 'a space', thousandsSeparator: ' ', masked: '$1 234 567.89', raw: '1234567.89' },
    { name: 'a multi-character separator', thousandsSeparator: '\'*', masked: '$1\'*234\'*567.89', raw: '1234567.89' },
    { name: 'a letter', thousandsSeparator: 'd', masked: '$1d234d567.89', raw: '1234567.89' },
    { name: 'no separator attribute', thousandsSeparator: undefined, masked: '$1234567.89', raw: '1234567.89' },
    { name: 'a unit after the number', thousandsSeparator: ',', unit: '€', masked: '1,234,567.89 €', raw: '1234567.89' },
    { name: 'an empty unit', thousandsSeparator: ',', unit: '', masked: '1,234,567.89', raw: '1234567.89' }
  ]

  for (const { name, thousandsSeparator, radix, unit, masked, raw } of cases) {
    test(`mounts and syncs the hidden input with ${name}`, () => {
      const hook = mountHook({ thousandsSeparator, radix, unit, value: masked })

      expect(() => hook.mounted()).not.toThrow()

      const mask = masks.at(-1)
      expect(mask.unmaskedValue).toBe(raw)
      expect(mask.listeners.accept).toHaveLength(1)

      mask.value = masked
      mask.listeners.accept[0]()
      expect(hook.hiddenInput.value).toBe(raw)

      expect(() => hook.updated()).not.toThrow()
      expect(hook.hiddenInput.value).toBe(raw)
    })
  }
})
