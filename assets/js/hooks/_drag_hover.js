/**
 * This hook adds hover styles on the upload dropzone when dragging a file over it.
 */
export default {
  mounted () {
    this.dragging = 0
    this.controller = new AbortController()
    const signal = this.controller.signal

    this.el.addEventListener('dragenter', () => this.dragChange(this.dragging + 1), { signal })
    this.el.addEventListener('dragleave', () => this.dragChange(this.dragging - 1), { signal })
    this.el.addEventListener('drop', () => this.dragChange(0), { signal })
  },
  destroyed () {
    this.controller.abort()
  },
  dragChange (value) {
    this.dragging = value
    this.el.firstElementChild.classList.toggle('border-primary', this.dragging > 0)
  }
}
