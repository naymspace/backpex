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
 *
 * Document listeners only run while the dropdown is open, so pages with many
 * dropdowns don't pay an event-handler tax for closed ones.
 */
export default {
  mounted () {
    this.trigger = this.el.querySelector(`#${this.el.id}-trigger`)
    this.menu = this.el.querySelector(`#${this.el.id}-menu`)
    if (!this.trigger) return

    this.isOpen = false
    this.mousedownInside = false

    this.handleRootMousedown = this.handleRootMousedown.bind(this)
    this.handleTriggerKeydown = this.handleTriggerKeydown.bind(this)
    this.handleDocumentMousedown = this.handleDocumentMousedown.bind(this)
    this.handleDocumentClick = this.handleDocumentClick.bind(this)
    this.handleDocumentKeydown = this.handleDocumentKeydown.bind(this)

    this.el.addEventListener('mousedown', this.handleRootMousedown)
    this.trigger.addEventListener('keydown', this.handleTriggerKeydown)
  },
  beforeUpdate () {
    // Remember which element inside the dropdown had focus, so we can restore
    // it after morphdom — LiveView's built-in focus preservation can drop focus
    // when the surrounding form is re-rendered, even though the input node
    // itself isn't replaced.
    this.focusedBeforeUpdate = this.el.contains(document.activeElement)
      ? document.activeElement
      : null
  },
  updated () {
    // Restore the open state across LiveView re-renders, since morphdom strips
    // classes that aren't in the server-rendered HTML.
    this.el.classList.toggle('dropdown-open', this.isOpen)

    if (this.focusedBeforeUpdate && !this.el.contains(document.activeElement)) {
      const target = this.focusedBeforeUpdate.isConnected
        ? this.focusedBeforeUpdate
        : this.focusedBeforeUpdate.id && this.el.querySelector(`#${this.focusedBeforeUpdate.id}`)
      target?.focus()
    }
    this.focusedBeforeUpdate = null
  },
  destroyed () {
    this.detachDocumentListeners()
    this.el.removeEventListener('mousedown', this.handleRootMousedown)
    this.trigger?.removeEventListener('keydown', this.handleTriggerKeydown)
  },
  open () {
    if (this.isOpen) return
    this.isOpen = true
    this.el.classList.add('dropdown-open')
    this.attachDocumentListeners()
  },
  close () {
    if (!this.isOpen) return
    this.isOpen = false
    this.mousedownInside = false
    this.el.classList.remove('dropdown-open')
    this.detachDocumentListeners()
  },
  toggle () {
    if (this.isOpen) this.close()
    else this.open()
  },
  attachDocumentListeners () {
    document.addEventListener('mousedown', this.handleDocumentMousedown, true)
    document.addEventListener('click', this.handleDocumentClick, true)
    document.addEventListener('keydown', this.handleDocumentKeydown)
  },
  detachDocumentListeners () {
    document.removeEventListener('mousedown', this.handleDocumentMousedown, true)
    document.removeEventListener('click', this.handleDocumentClick, true)
    document.removeEventListener('keydown', this.handleDocumentKeydown)
  },
  handleRootMousedown (event) {
    // mousedown reached `this.el`, so it's inside the dropdown. Set the flag
    // up front: when this mousedown is the one that *opens* the dropdown, the
    // document-level listener isn't attached yet and won't catch it.
    this.mousedownInside = true
    if (this.menu?.contains(event.target)) return
    this.toggle()
  },
  handleTriggerKeydown (event) {
    // Match WAI-ARIA button semantics: Enter and Space activate the trigger.
    if (event.key !== 'Enter' && event.key !== ' ') return
    event.preventDefault()
    this.toggle()
  },
  handleDocumentMousedown (event) {
    this.mousedownInside = this.el.contains(event.target)
  },
  handleDocumentClick (event) {
    if (this.el.contains(event.target)) return
    if (this.mousedownInside) {
      this.mousedownInside = false
      return
    }
    this.close()
  },
  handleDocumentKeydown (event) {
    if (event.key !== 'Escape') return
    this.close()
    this.trigger.focus()
  }
}
