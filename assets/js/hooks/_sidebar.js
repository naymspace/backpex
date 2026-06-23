/**
 * Manages sidebar open/close drawer state for mobile and desktop.
 *
 * Desktop: sidebar visible by default, content shifts when closed
 * Mobile: sidebar hidden by default, overlays content when opened
 */
export default {
  STORAGE_KEY: 'backpex-sidebar-open',
  FOCUSABLE_SELECTOR:
    'a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])',

  mounted () {
    this.sidebar = document.getElementById('backpex-sidebar')
    this.overlay = document.getElementById('backpex-sidebar-overlay')
    this.main = document.getElementById('backpex-main')
    this.toggleBtn = document.getElementById('backpex-sidebar-toggle')

    // No sidebar slot rendered; hook has nothing to do.
    if (!this.sidebar || !this.toggleBtn) return

    // State: mobile closed by default, desktop state from localStorage (default open)
    this.mobileOpen = false
    this.desktopOpen = this.loadDesktopState()
    // Element focused before the mobile drawer was opened, for focus restore.
    this.previousFocus = null

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
  },

  updated () {
    if (!this.sidebar || !this.toggleBtn) return
    this.applyState()
  },

  destroyed () {
    this.toggleBtn?.removeEventListener('click', this._onToggleClick)
    this.overlay?.removeEventListener('click', this._onOverlayClick)
    this.mediaQuery?.removeEventListener('change', this._onMediaChange)
    document.removeEventListener('keydown', this._onKeydown)
  },

  isDesktop () {
    return this.mediaQuery.matches
  },

  handleToggle () {
    if (this.isDesktop()) {
      this.desktopOpen = !this.desktopOpen
      this.saveDesktopState()
    } else {
      if (!this.mobileOpen) this.previousFocus = document.activeElement
      this.mobileOpen = !this.mobileOpen
    }
    this.applyState()
    if (!this.isDesktop() && this.mobileOpen) this.focusFirstInSidebar()
  },

  loadDesktopState () {
    const stored = localStorage.getItem(this.STORAGE_KEY)
    // Default to open if no stored value
    return stored === null ? true : stored === 'true'
  },

  saveDesktopState () {
    localStorage.setItem(this.STORAGE_KEY, this.desktopOpen.toString())
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

    // Declarative state: write data attributes and let CSS map them to the
    // translate / margin / overlay styles (see the app_shell classes). One
    // source of truth, and no inline styles fighting the SSR `lg:` defaults.
    this.sidebar.dataset.state = sidebarVisible ? 'open' : 'closed'

    // Remove off-canvas sidebar from tab order and accessibility tree
    this.sidebar.toggleAttribute('inert', !sidebarVisible)

    // Main content shifts only when the desktop sidebar is open.
    this.main.dataset.shift = isDesktop && this.desktopOpen ? 'on' : 'off'

    // Overlay is shown only for the open mobile drawer.
    this.overlay.dataset.visible = !isDesktop && this.mobileOpen ? 'on' : 'off'

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
  }
}
