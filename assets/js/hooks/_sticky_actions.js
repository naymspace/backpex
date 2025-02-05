/**
 * Hook to determine if a table row is horizontally scrollable (=> actions are sticky).
 *
 * Adds a 'stuck' attribute to the sticky element which can then be used for styling.
 */
export default {
  mounted() {
    const sticky = this.el.querySelector('.sticky')

    this.observer = new IntersectionObserver(
      ([entry]) => { sticky.toggleAttribute('stuck', entry.intersectionRatio < 1)},
      { threshold: [1], root: this.el.closest(".overflow-x-auto") }
    )

    this.observer.observe(this.el)
  },
  destroyed() {
    this.observer.disconnect()
  }
}
