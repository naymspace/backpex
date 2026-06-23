import { BackpexPreferences } from './_preferences'

/**
 * Handles sidebar section expand/collapse and persists each section's
 * open/closed state via BackpexPreferences (cookie + sessionStorage mirror).
 *
 * The sessionStorage mirror keeps the user's choice authoritative across the
 * hook re-mount LiveView performs on live_redirect, where the server
 * re-renders sections from a session snapshot frozen at websocket-connect
 * time. See assets/js/hooks/_preferences.js and the user preferences guide.
 */
export default {
  mounted () {
    // Per-toggle click handlers, keyed off the toggle element, so they can
    // be removed reliably (a fresh bound fn would never match).
    this._sectionHandlers = new WeakMap()
    // Client-authoritative section state, seeded per-section from the
    // sessionStorage mirror in initializeSections().
    this._sectionStates = {}
    this.initializeSections()
    this.applySectionStates()
  },

  updated () {
    this.initializeSections()
    this.applySectionStates()
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
      const toggle = section.querySelector('[data-menu-dropdown-toggle]')
      const content = section.querySelector('[data-menu-dropdown-content]')

      // sidebar_section always renders both, but guard so a malformed
      // section can't throw and break setup for every other section.
      if (!toggle || !content) return

      // Hide sections without content.
      if (!this.hasContent(content)) {
        section.style.display = 'none'
        return
      }

      section.classList.remove('hidden')

      // Prefer the sessionStorage mirror over the server-rendered attribute
      // the first time we see a section: on a fresh connect the cookie is
      // authoritative (and the mirror matches), but on a re-mount after
      // live_redirect the server re-rendered from a stale session snapshot
      // and the mirror is the only source of the user's intent.
      const id = section.dataset.sectionId
      if (!(id in this._sectionStates)) {
        this._sectionStates[id] = BackpexPreferences.get(
          `global.sidebar_section.${id}`,
          section.dataset.sectionOpen === 'true'
        )
      }

      const previous = this._sectionHandlers.get(toggle)
      if (previous) toggle.removeEventListener('click', previous)
      const handler = (e) => this.handleSectionToggle(e)
      this._sectionHandlers.set(toggle, handler)
      toggle.addEventListener('click', handler)
    })
  },

  // Re-apply the authoritative client-side open/closed state to the DOM.
  // Called from updated() to overwrite whatever the server just rendered from
  // a potentially-stale session snapshot after a live_redirect.
  applySectionStates () {
    for (const [id, open] of Object.entries(this._sectionStates)) {
      const section = this.el.querySelector(`[data-section-id="${id}"]`)
      if (!section) continue
      const toggle = section.querySelector('[data-menu-dropdown-toggle]')
      const content = section.querySelector('[data-menu-dropdown-content]')
      if (!toggle || !content) continue
      toggle.classList.toggle('menu-dropdown-show', open)
      toggle.setAttribute('aria-expanded', String(open))
      content.style.display = open ? '' : 'none'
      section.dataset.sectionOpen = String(open)
    }
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
    // Keep the data attribute in sync so future reconciliations read back
    // the current user-intended state.
    section.dataset.sectionOpen = String(isNowOpen)
    this._sectionStates[sectionId] = isNowOpen
    // Mirror the per-section boolean to sessionStorage (for live_redirect
    // re-mounts) and POST it to the cookie (for the next fresh connect). The
    // per-section key matches the flat form the server stores so
    // Backpex.Preferences.get_map/3 can reconstruct the nested map.
    BackpexPreferences.set(
      `global.sidebar_section.${sectionId}`,
      isNowOpen,
      { mirror: 'session' }
    )
  }
}
