/**
 * Handles the initial state of all sidebar sections and saves the state to localstorage on toggle.
 */
export default {
  mounted () {
    this.initializeSections()
  },
  updated () {
    this.initializeSections()
  },
  destroyed () {
    const sections = this.el.querySelectorAll('[data-section-id]')

    sections.forEach(section => {
      const toggle = section.querySelector('[data-menu-dropdown-toggle]')
      toggle.removeEventListener('click', this.handleToggle.bind(this))
    })
  },
  hasContent (element) {
    if (!element || element.children.length === 0) {
      return false
    }

    for (const child of element.children) {
      const childContent = child.querySelector('[data-menu-dropdown-content]')

      if (childContent) {
        if (this.hasContent(childContent)) {
          return true
        }
      } else {
        return true
      }
    }

    return false
  },
  initializeSections () {
    const sections = this.el.querySelectorAll('[data-section-id]')

    sections.forEach(section => {
      const sectionId = section.dataset.sectionId
      const toggle = section.querySelector('[data-menu-dropdown-toggle]')
      const content = section.querySelector('[data-menu-dropdown-content]')

      if (!this.hasContent(content)) {
        content.style.display = 'none'
        return
      }

      const isOpen = localStorage.getItem(`sidebar-section-${sectionId}`) === 'true'
      if (!isOpen) {
        toggle.classList.remove('menu-dropdown-show')
        content.style.display = 'none'
      }

      section.classList.remove('hidden')

      toggle.addEventListener('click', this.handleToggle.bind(this))
    })
  },
  handleToggle (event) {
    const section = event.currentTarget.closest('[data-section-id]')
    const sectionId = section.dataset.sectionId
    const toggle = section.querySelector('[data-menu-dropdown-toggle]')
    const content = section.querySelector('[data-menu-dropdown-content]')

    toggle.classList.toggle('menu-dropdown-show')
    content.style.display = content.style.display === 'none' ? 'block' : 'none'

    const isNowOpen = toggle.classList.contains('menu-dropdown-show')
    localStorage.setItem(`sidebar-section-${sectionId}`, isNowOpen)
  }
}
