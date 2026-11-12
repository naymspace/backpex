/**
 * Hook to determine if a table row is horizontally scrollable (=> actions are sticky).
 *
 * Adds a 'stuck' attribute to the sticky element which can then be used for styling.
 */
export default {
  mounted () {
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
    // Query on every call: patches (e.g. toggling columns) can replace the sticky cell.
    this.el.querySelector('.sticky')?.toggleAttribute('stuck', this.stuck === true)
  }
}
