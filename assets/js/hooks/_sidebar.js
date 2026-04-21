import { BackpexPreferences } from './_preferences'

// Sidebar state is persisted both to the cookie (for fresh connects) and to
// sessionStorage (for live_redirects). LiveView freezes the session at
// websocket-connect time, so a re-mount after `live_redirect` reads a stale
// cookie and the server re-renders the shell from its default. The
// sessionStorage mirror keeps the user's client-side choices authoritative
// until the next fresh connect re-seeds from the cookie.
//
// The mirror is handled by BackpexPreferences.get/set with
// `mirror: 'session'` — see assets/js/hooks/_preferences.js and the
// "Writing a JS hook that persists preferences" section of the user
// preferences guide. If you add another JS-driven UI-chrome preference,
// follow the same pattern instead of rolling your own sessionStorage layer.

/**
 * Manages sidebar open/close state for mobile and desktop and handles sidebar section expand/collapse.
 *
 * Desktop: sidebar visible by default, content shifts when closed
 * Mobile: sidebar hidden by default, overlays content when opened
 */
export default {
  FOCUSABLE_SELECTOR:
    'a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])',

  mounted () {
    this.sidebar = document.getElementById('backpex-sidebar')
    this.overlay = document.getElementById('backpex-sidebar-overlay')
    this.main = document.getElementById('backpex-main')
    this.toggleBtn = document.getElementById('backpex-sidebar-toggle')

    // No sidebar slot rendered; hook has nothing to do.
    if (!this.sidebar || !this.toggleBtn) return

    // State: mobile closed by default. Desktop state prefers the
    // sessionStorage mirror over the server-rendered data attribute — same
    // live_redirect staleness reason as the section states below.
    this.mobileOpen = false
    this.desktopOpen = BackpexPreferences.get(
      'global.sidebar_open',
      this.el.dataset.sidebarOpen === 'true'
    )
    // Element focused before the mobile drawer was opened, for focus restore.
    this.previousFocus = null
    // Per-toggle click handlers, keyed off the toggle element (section dropdowns).
    this._sectionHandlers = new WeakMap()
    // Client-authoritative section state. Populated per-section from the
    // sessionStorage mirror in initializeSections(); unknown sections fall
    // back to the server-rendered data-section-open there. Seeding from
    // sessionStorage is what lets section state survive the hook re-mount
    // LiveView performs on live_redirect between LiveViews (the
    // websocket-frozen session the server re-renders from is stale, see
    // the top-of-file comment).
    this._sectionStates = {}

    // Track Tailwind's lg breakpoint via its CSS custom property so CSS
    // `lg:` utilities and this hook stay in sync if the user customizes it.
    // Falls back to the Tailwind v4 default when the variable is not defined.
    const breakpoint =
      getComputedStyle(document.documentElement)
        .getPropertyValue('--breakpoint-lg')
        .trim() || '64rem'
    this.mediaQuery = window.matchMedia(`(min-width: ${breakpoint})`)

    // Apply initial state (CSS sets visible by default, JS hides on mobile)
    this.applyState()

    // Re-enable transitions on the next frame so the initial snap to the
    // stored desktop preference doesn't animate on first paint.
    requestAnimationFrame(() => {
      this.sidebar.removeAttribute('data-suppress-transition')
      this.main.removeAttribute('data-suppress-transition')
    })

    // Event listeners (bound so they can be removed in destroyed())
    this._onToggleClick = () => this.handleToggle()
    this._onOverlayClick = () => this.closeMobile()
    this._onMediaChange = (e) => this.handleResize(e)
    this._onKeydown = (e) => this.handleKeydown(e)

    this.toggleBtn.addEventListener('click', this._onToggleClick)
    this.overlay.addEventListener('click', this._onOverlayClick)
    this.mediaQuery.addEventListener('change', this._onMediaChange)

    document.addEventListener('keydown', this._onKeydown)

    // Initialize sidebar sections, then re-assert stored state over whatever
    // the server just rendered (which may have been rendered from a stale
    // session snapshot during a live_redirect).
    this.initializeSections()
    this.applySectionStates()
  },

  updated () {
    if (!this.sidebar || !this.toggleBtn) return
    this.applyState()
    this.initializeSections()
    this.applySectionStates()
  },

  destroyed () {
    this.toggleBtn?.removeEventListener('click', this._onToggleClick)
    this.overlay?.removeEventListener('click', this._onOverlayClick)
    this.mediaQuery?.removeEventListener('change', this._onMediaChange)
    document.removeEventListener('keydown', this._onKeydown)

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

  isDesktop () {
    return this.mediaQuery.matches
  },

  handleToggle () {
    if (this.isDesktop()) {
      this.desktopOpen = !this.desktopOpen
      // mirror: 'session' writes sessionStorage first, then POSTs to the
      // cookie for the next fresh connect.
      BackpexPreferences.set('global.sidebar_open', this.desktopOpen, { mirror: 'session' })
    } else {
      if (!this.mobileOpen) this.previousFocus = document.activeElement
      this.mobileOpen = !this.mobileOpen
    }
    this.applyState()
    if (!this.isDesktop() && this.mobileOpen) this.focusFirstInSidebar()
  },

  closeMobile () {
    const wasOpen = this.mobileOpen
    this.mobileOpen = false
    this.applyState()
    if (wasOpen) this.restorePreviousFocus()
  },

  handleResize (event) {
    if (event.matches) {
      this.mobileOpen = false
      this.previousFocus = null
    }
    this.applyState()
  },

  handleKeydown (event) {
    if (!this.mobileOpen || this.isDesktop()) return

    if (event.key === 'Escape') {
      this.closeMobile()
      return
    }

    if (event.key === 'Tab') this.trapTab(event)
  },

  trapTab (event) {
    const focusable = this.sidebar.querySelectorAll(this.FOCUSABLE_SELECTOR)
    if (focusable.length === 0) {
      event.preventDefault()
      return
    }

    const first = focusable[0]
    const last = focusable[focusable.length - 1]
    const active = document.activeElement

    if (event.shiftKey && (active === first || !this.sidebar.contains(active))) {
      event.preventDefault()
      last.focus()
    } else if (!event.shiftKey && active === last) {
      event.preventDefault()
      first.focus()
    }
  },

  focusFirstInSidebar () {
    const focusable = this.sidebar.querySelector(this.FOCUSABLE_SELECTOR)
    if (focusable) focusable.focus()
  },

  restorePreviousFocus () {
    if (this.previousFocus && document.contains(this.previousFocus)) {
      this.previousFocus.focus()
    }
    this.previousFocus = null
  },

  applyState () {
    const isDesktop = this.isDesktop()
    const sidebarVisible = isDesktop ? this.desktopOpen : this.mobileOpen

    // Sidebar position. The SSR classes -translate-x-full lg:translate-x-0
    // compile to the CSS `translate` property in Tailwind v4, so we must
    // write to the same property to win over them.
    this.sidebar.style.translate = sidebarVisible ? '0' : '-100%'

    // Remove off-canvas sidebar from tab order and accessibility tree
    this.sidebar.toggleAttribute('inert', !sidebarVisible)

    // Main content margin (desktop only, uses CSS variable)
    const showMargin = isDesktop && this.desktopOpen
    this.main.style.marginLeft = showMargin ? 'var(--sidebar-width, 16rem)' : '0'

    // Overlay (mobile only)
    const showOverlay = !isDesktop && this.mobileOpen
    this.overlay.classList.toggle('opacity-0', !showOverlay)
    this.overlay.classList.toggle('pointer-events-none', !showOverlay)
    this.overlay.classList.toggle('opacity-100', showOverlay)
    this.overlay.classList.toggle('pointer-events-auto', showOverlay)

    // ARIA
    this.toggleBtn.setAttribute('aria-expanded', sidebarVisible.toString())

    // Mobile drawer behaves as a modal dialog; desktop is inline chrome.
    if (!isDesktop && this.mobileOpen) {
      this.sidebar.setAttribute('role', 'dialog')
      this.sidebar.setAttribute('aria-modal', 'true')
    } else {
      this.sidebar.removeAttribute('role')
      this.sidebar.removeAttribute('aria-modal')
    }
  },

  // Sidebar Sections

  initializeSections () {
    const sections = this.el.querySelectorAll('[data-section-id]')

    sections.forEach((section) => {
      const toggle = section.querySelector('[data-menu-dropdown-toggle]')
      const content = section.querySelector('[data-menu-dropdown-content]')

      // Hide sections without content
      if (!this.hasContent(content)) {
        section.style.display = 'none'
        return
      }

      section.classList.remove('hidden')

      // Prefer the sessionStorage mirror over the server-rendered attribute
      // the first time we see a section: on a fresh websocket connect the
      // cookie is authoritative (and the mirror matches), but on a re-mount
      // after live_redirect the server re-rendered from a stale session
      // snapshot and the mirror is the only source of the user's intent.
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
    // re-mounts) and POST it to the cookie (for the next fresh connect).
    // The per-section key matches the flat form the server stores so
    // Backpex.Preferences.get_map/3 can reconstruct the nested map.
    BackpexPreferences.set(
      `global.sidebar_section.${sectionId}`,
      isNowOpen,
      { mirror: 'session' }
    )
  }
}
