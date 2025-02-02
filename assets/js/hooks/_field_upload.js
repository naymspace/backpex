/**
 * Companion hook for `Backpex.Fields.Upload`.
 */
export default {
  mounted() {
    this.dragging = 0
    this.dropTarget = this.el.querySelector("[phx-drop-target]")
    this.hiddenInput = this.el.querySelector("input[type='hidden']")

    this.dropTarget.addEventListener("dragenter", () => { this.dragChange(this.dragging + 1) })
    this.dropTarget.addEventListener("dragleave", () => { this.dragChange(this.dragging - 1) })
    this.dropTarget.addEventListener("drop", () => { this.dragChange(0) })

    const uploadKey = this.el.dataset.uploadKey
    this.handleEvent(`cancel-entry:${uploadKey}`, (e) => { this.dispatchChangeEvent() })
    this.handleEvent(`cancel-existing-entry:${uploadKey}`, (e) => { this.dispatchChangeEvent() })
  },
  dragChange(value) {
    this.dragging = value
    this.dropTarget.firstElementChild.classList.toggle("border-primary", this.dragging > 0)
  },
  dispatchChangeEvent() {
    form = document.getElementById('resource-form')

    if (form) {
      this.hiddenInput.dispatchEvent(new Event('input', { bubbles: true }))
    }
  }
}
