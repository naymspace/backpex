/**
 * Hook to determine if a table row is horizontally scrollable (=> actions are sticky).
 *
 * Adds a 'stuck' attribute to the sticky element which can then be used for styling.
 */
export default {
  mounted () {
    this.sticky = this.el.querySelector('.sticky')

    this.observer = new IntersectionObserver(
      ([entry]) => {
        this.stuck = entry.intersectionRatio < 1
        this.toggleStuckAttribute()
      },
      { threshold: [1], root: this.el.closest('.overflow-x-auto') }
    )

    this.observer.observe(this.el)
  },
  updated () {
    this.toggleStuckAttribute()
  },
  destroyed () {
    this.observer.disconnect()
  },
  toggleStuckAttribute () {
    this.sticky.toggleAttribute('stuck', this.stuck)
  }
}
