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
  initializeSections () {
    const sections = this.el.querySelectorAll('[data-section-id]')

    sections.forEach(section => {
      const sectionId = section.dataset.sectionId
      const toggle = section.querySelector('[data-menu-dropdown-toggle]')
      const content = section.querySelector('[data-menu-dropdown-content]')

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
