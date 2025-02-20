/**
 * This hooks displays a statically positioned tooltip which is not affected by parent elements and their overflow.
 */
export default {
  mounted () {
    this.tooltip = null

    this.handleMouseEnter = () => {
      const text = this.el.getAttribute('data-tooltip')
      if (!text) return

      this.tooltip = document.createElement('div')
      this.tooltip.innerText = text
      this.tooltip.className = `
        fixed z-50 -translate-x-1/2 px-2 py-1 bg-neutral  rounded-btn
        text-neutral-content text-sm shadow-sm whitespace-nowrap
        before:content-['']
        before:absolute before:w-0 before:h-0 before:left-1/2 before:-translate-x-1/2 before:top-full
        before:border-l-4 before:border-r-4 before:border-t-4 before:border-transparent before:border-t-neutral
      `

      document.body.appendChild(this.tooltip)
      this.updateTooltipPosition()
    }

    this.handleMouseLeave = () => {
      if (this.tooltip) {
        this.tooltip.remove()
        this.tooltip = null
      }
    }

    this.updateTooltipPosition = () => {
      if (!this.tooltip) return
      const rect = this.el.getBoundingClientRect()
      this.tooltip.style.left = `${rect.left + rect.width / 2}px`
      this.tooltip.style.top = `${rect.top - this.tooltip.offsetHeight - 6}px`
    }

    this.el.addEventListener('mouseenter', this.handleMouseEnter)
    this.el.addEventListener('mouseleave', this.handleMouseLeave)
    window.addEventListener('scroll', this.updateTooltipPosition)
  },
  destroyed () {
    this.el.removeEventListener('mouseenter', this.handleMouseEnter)
    this.el.removeEventListener('mouseleave', this.handleMouseLeave)
    window.removeEventListener('scroll', this.updateTooltipPosition)

    if (this.tooltip) {
      this.tooltip.remove()
    }
  }
}
