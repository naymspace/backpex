/**
 * This hook adds hover styles on the upload dropzone when dragging a file over it.
 */
export default {
  mounted() {
    this.dragging = 0
    this.el.addEventListener("dragenter", () => { this.dragChange(this.dragging + 1) })
    this.el.addEventListener("dragleave", () => { this.dragChange(this.dragging - 1) })
    this.el.addEventListener("drop", () => { this.dragChange(0) })
  },
  dragChange(value) {
    this.dragging = value
    this.el.firstElementChild.classList.toggle("border-primary", this.dragging > 0)
  }
}
