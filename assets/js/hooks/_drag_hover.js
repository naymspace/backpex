/**
 * This hook adds hover styles on the upload dropzone when dragging a file over it.
 */
export default {
  mounted() {
    this.dragging = 0

    this.dragenterHandler = () => this.dragChange(this.dragging + 1)
    this.dragleaveHandler = () => this.dragChange(this.dragging - 1)
    this.dropHandler = () => this.dragChange(0)
    
    this.el.addEventListener("dragenter", this.dragenterHandler)
    this.el.addEventListener("dragleave", this.dragleaveHandler)
    this.el.addEventListener("drop", this.dropHandler)
  },
  dragChange(value) {
    this.dragging = value
    this.el.firstElementChild.classList.toggle("border-primary", this.dragging > 0)
  },
  destroyed() {
    this.el.removeEventListener("dragenter", this.dragenterHandler)
    this.el.removeEventListener("dragleave", this.dragleaveHandler)
    this.el.removeEventListener("drop", this.dropHandler)
  }
}
