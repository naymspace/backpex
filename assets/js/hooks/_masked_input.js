import IMask from 'imask'

export default {
  mounted () {
    this.maskedInput = this.el.querySelector('[data-masked-input]')
    this.hiddenInput = this.el.querySelector('[data-hidden-input]')

    this.initializeMask()
  },
  initializeMask () {
    const maskPattern = this.el.dataset.unit ? `num ${this.el.dataset.unit}` : 'num'

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
  },
  destroyed () {
    this.mask.destroy()
  }
}
