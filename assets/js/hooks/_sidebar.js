/**
 * Manages sidebar open/close state for mobile and desktop and handles sidebar section expand/collapse.
 *
 * Desktop: sidebar visible by default, content shifts when closed
 * Mobile: sidebar hidden by default, overlays content when opened
 */
export default {
  MOBILE_BREAKPOINT: 768,
  STORAGE_KEY: 'backpex-sidebar-open',

  mounted () {
    this.sidebar = document.getElementById('backpex-sidebar')
    this.overlay = document.getElementById('backpex-sidebar-overlay')
    this.main = document.getElementById('backpex-main')
    this.toggleBtn = document.getElementById('backpex-sidebar-toggle')

    // State: mobile closed by default, desktop state from localStorage (default open)
    this.mobileOpen = false
    this.desktopOpen = this.loadDesktopState()

    // Apply initial state (CSS sets visible by default, JS hides on mobile)
    this.applyState()

    // Event listeners
    this.toggleBtn.addEventListener('click', () => this.handleToggle())
    this.overlay.addEventListener('click', () => this.closeMobile())

    this.mediaQuery = window.matchMedia(
      `(min-width: ${this.MOBILE_BREAKPOINT}px)`
    )
    this.mediaQuery.addEventListener('change', (e) => this.handleResize(e))

    document.addEventListener('keydown', (e) => this.handleKeydown(e))

    // Initialize sidebar sections
    this.initializeSections()
  },

  updated () {
    this.applyState()
    this.initializeSections()
  },

  isDesktop () {
    return window.innerWidth >= this.MOBILE_BREAKPOINT
  },

  handleToggle () {
    if (this.isDesktop()) {
      this.desktopOpen = !this.desktopOpen
      this.saveDesktopState()
    } else {
      this.mobileOpen = !this.mobileOpen
    }
    this.applyState()
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
    this.mobileOpen = false
    this.applyState()
  },

  handleResize (event) {
    if (event.matches) {
      this.mobileOpen = false
    }
    this.applyState()
  },

  handleKeydown (event) {
    if (event.key === 'Escape' && this.mobileOpen && !this.isDesktop()) {
      this.closeMobile()
    }
  },

  applyState () {
    const isDesktop = this.isDesktop()
    const sidebarVisible = isDesktop ? this.desktopOpen : this.mobileOpen

    // Sidebar transform
    this.sidebar.classList.toggle('-translate-x-full', !sidebarVisible)
    this.sidebar.classList.toggle('translate-x-0', sidebarVisible)

    // Main content margin (desktop only, uses CSS variable)
    const showMargin = isDesktop && this.desktopOpen
    this.main.classList.toggle('ml-[var(--sidebar-width,16rem)]', showMargin)
    this.main.classList.toggle('ml-0', !showMargin)

    // Overlay (mobile only)
    const showOverlay = !isDesktop && this.mobileOpen
    this.overlay.classList.toggle('opacity-0', !showOverlay)
    this.overlay.classList.toggle('pointer-events-none', !showOverlay)
    this.overlay.classList.toggle('opacity-100', showOverlay)
    this.overlay.classList.toggle('pointer-events-auto', showOverlay)

    // ARIA
    this.toggleBtn.setAttribute('aria-expanded', sidebarVisible.toString())
  },

  // Sidebar Sections

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

      toggle.removeEventListener('click', toggle._handler)
      toggle._handler = (e) => this.handleSectionToggle(e)
      toggle.addEventListener('click', toggle._handler)
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
