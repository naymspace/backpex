/**
 * Manages dropdown open state programmatically via the `dropdown-open` class.
 *
 * daisyUI's CSS-only dropdown relies on `:focus-within` to stay open. That
 * mechanism breaks when the dropdown contains a native form control like a
 * `<select>`: in some Chromium-based browsers (notably Brave and Edge),
 * opening a native picker moves focus to `<body>`, so `:focus-within` flips to
 * false and the dropdown collapses mid-interaction.
 *
 * Two daisyUI behaviors complicate the JS toggle:
 *
 *   1. While the dropdown is open, daisyUI applies `pointer-events: none` to
 *      the trigger. Pointer events at the trigger's position then re-target
 *      to the dropdown root, so a listener attached to the trigger element
 *      wouldn't fire on the close-on-second-click. Listen on the root and
 *      treat any mousedown that's *not* inside the menu as a toggle — that
 *      covers both the trigger (first click) and the re-targeted root
 *      (second click).
 *
 *   2. After dismissing a native picker, Chromium sometimes fires a
 *      synthesized "light-dismiss" click on the page underneath, without a
 *      preceding mousedown there. The outside-click handler tracks where the
 *      last mousedown landed and ignores outside clicks whose mousedown was
 *      inside the dropdown.
 */
export default {
  mounted () {
    this.trigger = this.el.querySelector(`#${this.el.id}-trigger`)
    this.menu = this.el.querySelector(`#${this.el.id}-menu`)
    if (!this.trigger) return

    this.isOpen = false
    this.mousedownInside = false

    this.handleRootMousedown = this.handleRootMousedown.bind(this)
    this.handleDocumentMousedown = this.handleDocumentMousedown.bind(this)
    this.handleDocumentClick = this.handleDocumentClick.bind(this)
    this.handleKeydown = this.handleKeydown.bind(this)

    this.el.addEventListener('mousedown', this.handleRootMousedown)
    document.addEventListener('mousedown', this.handleDocumentMousedown, true)
    document.addEventListener('click', this.handleDocumentClick, true)
    document.addEventListener('keydown', this.handleKeydown)
  },
  updated () {
    // Restore the open state across LiveView re-renders, since morphdom strips
    // classes that aren't in the server-rendered HTML.
    this.el.classList.toggle('dropdown-open', this.isOpen)
  },
  destroyed () {
    document.removeEventListener('mousedown', this.handleDocumentMousedown, true)
    document.removeEventListener('click', this.handleDocumentClick, true)
    document.removeEventListener('keydown', this.handleKeydown)
  },
  handleRootMousedown (event) {
    // Toggle when the mousedown hits anywhere outside the menu. We can't just
    // check `this.trigger.contains(event.target)` because daisyUI applies
    // `pointer-events: none` to the trigger while the dropdown is open — the
    // event then re-targets to the dropdown root, not the trigger.
    if (this.menu?.contains(event.target)) return
    this.isOpen = !this.isOpen
    this.el.classList.toggle('dropdown-open', this.isOpen)
  },
  handleDocumentMousedown (event) {
    this.mousedownInside = this.el.contains(event.target)
  },
  handleDocumentClick (event) {
    if (!this.isOpen) return
    if (this.el.contains(event.target)) return
    if (this.mousedownInside) {
      this.mousedownInside = false
      return
    }
    this.isOpen = false
    this.el.classList.remove('dropdown-open')
  },
  handleKeydown (event) {
    if (event.key !== 'Escape' || !this.isOpen) return
    this.isOpen = false
    this.el.classList.remove('dropdown-open')
    this.trigger.focus()
  }
}
