import { BackpexPreferences } from './_preferences'

// Sidebar state is persisted through BackpexPreferences with
// `mirror: 'session'`, which covers all three ways this shell gets rendered:
//
// - Fresh connect: the server reads the preference adapter and renders
//   `data-sidebar-open`.
// - live_redirect: no HTTP request happens and LiveView freezes the session at
//   websocket-connect time, so the server re-renders the shell from a stale
//   snapshot. The sessionStorage mirror, handed back in the connect params,
//   keeps the user's choice authoritative.
// - Reload right after a toggle: the POST has not landed yet, so the session
//   cookie the document GET carries is one write behind. The short-lived
//   `backpex_prefs` cookie carries the unacknowledged write to the dead render.
//
// The server therefore only ever has NEW information for this hook when the
// write it is rendering has been acknowledged — which is exactly the condition
// `updated()` adopts on. See assets/js/hooks/_preferences.js and the "Writing a
// JS hook that persists preferences" section of the user preferences guide. If
// you add another JS-driven UI-chrome preference, follow the same pattern
// instead of rolling your own sessionStorage layer.

/**
 * Manages sidebar open/close drawer state for mobile and desktop.
 *
 * Desktop: sidebar visible by default, content shifts when closed
 * Mobile: sidebar hidden by default, overlays content when opened
 *
 * Section expand/collapse lives in the separate BackpexSidebarSections hook.
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
    // live_redirect staleness reason as the section states. By the time hooks
    // mount, connectParams() has primed the mirror, so the two agree unless
    // this tab holds an unacknowledged write — in which case the mirror is
    // right and the attribute may not be.
    this.mobileOpen = false
    this.desktopOpen = BackpexPreferences.get(
      'global.sidebar_open',
      this.el.dataset.sidebarOpen === 'true'
    )
    // Last server-rendered value, so updated() can tell a *changed* attribute
    // (new information) from the server merely re-rendering what it had.
    this.serverOpen = this.el.dataset.sidebarOpen === 'true'
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

    this.releaseTransitions()

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

    // Edge-triggered: `desktopOpen` drives higher-specificity `data-[state]`
    // classes, so re-asserting a stale cached value on every render would
    // permanently override the server. Adopt the attribute only when it
    // *changed* — and only when this tab has no write the server has yet to
    // acknowledge, since such a render was necessarily produced without it.
    const serverOpen = this.el.dataset.sidebarOpen === 'true'
    if (serverOpen !== this.serverOpen) {
      this.serverOpen = serverOpen
      if (!BackpexPreferences.isPending('global.sidebar_open')) this.desktopOpen = serverOpen
    }

    this.applyState()

    // `data-suppress-transition` is static markup, so any patch that re-renders
    // the shell — a live_patch from sorting or filtering, say — morphs it back
    // onto these elements. Nothing else takes it off again, which left the
    // sidebar unable to animate for the rest of the page load.
    this.releaseTransitions()
  },

  destroyed () {
    this.toggleBtn?.removeEventListener('click', this._onToggleClick)
    this.overlay?.removeEventListener('click', this._onOverlayClick)
    this.mediaQuery?.removeEventListener('change', this._onMediaChange)
    document.removeEventListener('keydown', this._onKeydown)

    // Drop inert in case the hook is torn down while the mobile drawer is open
    // so the main content doesn't stay unreachable across live_redirects.
    this.main?.removeAttribute('inert')
  },

  // `data-suppress-transition` is server-rendered so the correction applyState()
  // may have just made — the mirror disagreeing with a dead render one write
  // behind — snaps instead of animating. Releasing it in the same style-change
  // event that applies that correction defeats it: a transition starts from the
  // *after-change* style, so the suppressed before-change style buys nothing and
  // the sidebar slides for 300ms instead. Force the corrected state through a
  // style recalculation while still suppressed, so it becomes the before-change
  // style, then release against an unchanged value.
  //
  // Deliberately synchronous rather than requestAnimationFrame: rAF never fires
  // in a background tab, which would strand the guard and leave the sidebar
  // unable to animate for the rest of the page load.
  releaseTransitions () {
    if (
      !this.sidebar.hasAttribute('data-suppress-transition') &&
      !this.main.hasAttribute('data-suppress-transition')
    ) return

    // Reading layout flushes the pending style change.
    this.sidebar.getBoundingClientRect()
    this.main.getBoundingClientRect()

    this.sidebar.removeAttribute('data-suppress-transition')
    this.main.removeAttribute('data-suppress-transition')
  },

  isDesktop () {
    return this.mediaQuery.matches
  },

  handleToggle () {
    if (this.isDesktop()) {
      this.desktopOpen = !this.desktopOpen
      // Writes the sessionStorage mirror and marks the key pending in the
      // `backpex_prefs` cookie, both synchronously, before POSTing. Until that
      // POST responds this value beats anything the server renders.
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
    const focusable = this.visibleFocusable()
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

  // Focusable descendants that are actually rendered. Links inside a
  // collapsed section are display:none (offsetParent === null); leaving
  // them in would anchor the trap's first/last on an unfocusable element
  // and let Tab escape the modal drawer. No focusable inside the sidebar
  // is position:fixed, so a null offsetParent reliably means hidden here.
  visibleFocusable () {
    return Array.from(this.sidebar.querySelectorAll(this.FOCUSABLE_SELECTOR))
      .filter((el) => el.offsetParent !== null)
  },

  focusFirstInSidebar () {
    const focusable = this.visibleFocusable()[0]
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

    // aria-modal needs a matching inert region; the topbar and main content
    // live inside #backpex-main, so inerting that element covers both.
    this.main.toggleAttribute('inert', !isDesktop && this.mobileOpen)
  }
}
