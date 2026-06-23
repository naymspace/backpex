/**
 * Handles the initial state of all sidebar sections and persists each
 * section's open/closed state to localStorage on toggle.
 */
export default {
  mounted () {
    // Per-toggle click handlers, keyed off the toggle element, so they can
    // be removed reliably (a fresh bound fn would never match).
    this._sectionHandlers = new WeakMap()
    this.initializeSections()
  },

  updated () {
    this.initializeSections()
  },

  destroyed () {
    const sections = this.el.querySelectorAll('[data-section-id]')
    sections.forEach((section) => {
      const toggle = section.querySelector('[data-menu-dropdown-toggle]')
      const handler = toggle && this._sectionHandlers.get(toggle)
      if (handler) {
        toggle.removeEventListener('click', handler)
        this._sectionHandlers.delete(toggle)
      }
    })
  },

  initializeSections () {
    const sections = this.el.querySelectorAll('[data-section-id]')

    sections.forEach((section) => {
      const sectionId = section.dataset.sectionId
      const toggle = section.querySelector('[data-menu-dropdown-toggle]')
      const content = section.querySelector('[data-menu-dropdown-content]')

      if (!this.hasContent(content)) {
        content.style.display = 'none'
        return
      }

      const isOpen =
        localStorage.getItem(`sidebar-section-${sectionId}`) === 'true'
      if (!isOpen) {
        toggle.classList.remove('menu-dropdown-show')
        toggle.setAttribute('aria-expanded', 'false')
        content.style.display = 'none'
      } else {
        toggle.setAttribute('aria-expanded', 'true')
      }

      section.classList.remove('hidden')

      const previous = this._sectionHandlers.get(toggle)
      if (previous) toggle.removeEventListener('click', previous)
      const handler = (e) => this.handleSectionToggle(e)
      this._sectionHandlers.set(toggle, handler)
      toggle.addEventListener('click', handler)
    })
  },

  hasContent (element) {
    if (!element || element.children.length === 0) return false
    for (const child of element.children) {
      const childContent = child.querySelector('[data-menu-dropdown-content]')
      if (childContent) {
        if (this.hasContent(childContent)) return true
      } else {
        return true
      }
    }
    return false
  },

  handleSectionToggle (event) {
    const section = event.currentTarget.closest('[data-section-id]')
    const sectionId = section.dataset.sectionId
    const toggle = section.querySelector('[data-menu-dropdown-toggle]')
    const content = section.querySelector('[data-menu-dropdown-content]')

    toggle.classList.toggle('menu-dropdown-show')
    content.style.display = content.style.display === 'none' ? 'block' : 'none'

    const isNowOpen = toggle.classList.contains('menu-dropdown-show')
    toggle.setAttribute('aria-expanded', isNowOpen.toString())
    localStorage.setItem(`sidebar-section-${sectionId}`, isNowOpen)
  }
}
