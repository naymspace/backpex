import IMask from 'imask'

export default {
  mounted () {
    this.maskedInput = this.el.querySelector('[data-masked-input]')
    this.hiddenInput = this.el.querySelector('[data-hidden-input]')

    this.initializeMask()
  },
  initializeMask () {
    const maskPattern = this.el.dataset.maskPattern

    if (!maskPattern) {
      console.error('You must provide a mask pattern in the data-masked-pattern attribute.')
      return
    }

    this.maskOptions = {
      mask: maskPattern,
      lazy: false,
      blocks: {
        num: {
          mask: Number,
          thousandsSeparator: this.el.dataset.thousandsSeparator,
          radix: this.el.dataset.radix
        }
      }
    }

    this.mask = IMask(this.maskedInput, this.maskOptions)
    this.mask.unmaskedValue = this.rawValue(this.hiddenInput.value)
    this.mask.on('accept', this.handleMaskChange.bind(this))
  },
  updated () {
    this.handleMaskChange()
  },
  handleMaskChange () {
    this.hiddenInput.value = this.rawValue(this.mask.value)
    this.hiddenInput.dispatchEvent(new Event('input', { bubbles: true }))
  },
  rawValue (value) {
    return value
      .replace(this.el.dataset.unit || '', '')
      .trim()
      .replace(new RegExp(`\\${this.el.dataset.thousandsSeparator}`, 'g'), '')
  },
  destroyed () {
    this.mask.destroy()
  }
}
