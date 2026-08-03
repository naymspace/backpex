import { BackpexPreferences } from './_preferences'

/**
 * Handles sidebar section expand/collapse and persists each section's
 * open/closed state via BackpexPreferences.
 *
 * Same three-render story as _sidebar.js: the sessionStorage mirror keeps the
 * user's choice authoritative across the hook re-mount LiveView performs on
 * live_redirect (the server re-renders sections from a session snapshot frozen
 * at websocket-connect time), and the short-lived `backpex_prefs` cookie
 * carries a not-yet-acknowledged toggle to the dead render of a fast reload.
 * The server only has NEW information here once it has acknowledged the write,
 * which is the condition initializeSections() adopts a changed
 * `data-section-open` on. See assets/js/hooks/_preferences.js and the user
 * preferences guide.
 *
 * `data-section-open` is SERVER-OWNED: this hook reads it as the baseline for
 * that comparison and never writes it. The visual and a11y state it applies
 * lives in `menu-dropdown-show`, `aria-expanded` and the content's display.
 */
export default {
  mounted () {
    BackpexPreferences.syncScope()
    this.preferenceScopeMarker = BackpexPreferences.scopeMarker
    // Per-toggle click handlers, keyed off the toggle element, so they can
    // be removed reliably (a fresh bound fn would never match).
    this._sectionHandlers = new WeakMap()
    // Client-authoritative section state, seeded per-section from the
    // sessionStorage mirror in initializeSections().
    this._sectionStates = {}
    // Last server-rendered `data-section-open` per section, so a *changed*
    // attribute (new information) is distinguishable from a re-render.
    this._serverStates = {}
    this.initializeSections()
    this.applySectionStates()
  },

  updated () {
    BackpexPreferences.syncScope()
    const preferenceScopeMarker = BackpexPreferences.scopeMarker

    if (this.preferenceScopeMarker !== preferenceScopeMarker) {
      this.preferenceScopeMarker = preferenceScopeMarker
      this._sectionStates = {}
      this._serverStates = {}
    }

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

      // Seed once from the sessionStorage mirror, preferring it over the
      // server-rendered attribute: on a fresh connect the two agree, but on a
      // re-mount after live_redirect the server re-rendered from a stale
      // session snapshot and the mirror is the only source of the user's
      // intent.
      //
      // Afterwards, reconcile edge-triggered. A cached state re-asserted on
      // every render would give the server no path to ever correct this hook;
      // adopting the attribute unconditionally would undo a click the server
      // has not seen yet. So: adopt it when it *changed*, unless this tab holds
      // a write the server has not acknowledged.
      const id = section.dataset.sectionId
      const key = `global.sidebar_section.${id}`
      const serverOpen = section.dataset.sectionOpen === 'true'

      if (!(id in this._sectionStates)) {
        this._sectionStates[id] = BackpexPreferences.get(key, serverOpen)
        this._serverStates[id] = serverOpen
      } else if (this._serverStates[id] !== serverOpen) {
        this._serverStates[id] = serverOpen
        if (!BackpexPreferences.isPending(key)) this._sectionStates[id] = serverOpen
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
  //
  // Deliberately does not touch `data-section-open`: that attribute is the
  // server's, and it is the baseline initializeSections() compares against.
  // Writing it here would make the hook compare against its own writes.
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
    this._sectionStates[sectionId] = isNowOpen
    // Mirror the per-section boolean to sessionStorage (for live_redirect
    // re-mounts), mark it pending in the `backpex_prefs` cookie (for the dead
    // render of a reload that beats the POST) and persist it. The per-section
    // key matches the flat form the server stores so
    // Backpex.Preferences.get_map/3 can reconstruct the nested map.
    BackpexPreferences.set(
      `global.sidebar_section.${sectionId}`,
      isNowOpen,
      { mirror: 'session' }
    )
  }
}
