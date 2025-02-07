/**
 * This hook dispatches a form change/input event on the hidden upload field when cancelling an entry.
 * This makes errors validation on upload fields work.
 */
export default {
  mounted () {
    this.form = this.el.closest('form')

    const uploadKey = this.el.dataset.uploadKey
    this.handleEvent(`cancel-entry:${uploadKey}`, (e) => { this.dispatchChangeEvent() })
    this.handleEvent(`cancel-existing-entry:${uploadKey}`, (e) => { this.dispatchChangeEvent() })
  },
  dispatchChangeEvent() {
    if (this.form) {
      this.el.dispatchEvent(new Event('input', { bubbles: true }))
    }
  }
}
