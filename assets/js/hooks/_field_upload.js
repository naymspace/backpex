/**
 * Companion hook for `Backpex.Fields.Upload`.
 */
export default {
  mounted() {
    this.dragging = 0
    this.dropTarget = this.el.querySelector("[phx-drop-target]")

    this.dropTarget.addEventListener("dragenter", () => { this.dragChange(this.dragging + 1) })
    this.dropTarget.addEventListener("dragleave", () => { this.dragChange(this.dragging - 1) })
    this.dropTarget.addEventListener("drop", () => { this.dragChange(0) })
  },
  dragChange(value) {
    this.dragging = value
    this.dropTarget.firstElementChild.classList.toggle("border-primary", this.dragging > 0)
  }
}
