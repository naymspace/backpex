/**
 * Handles the initial state of all sidebar sections and saves the state to localstorage on toggle.
 */
export default {
  mounted() {
    window.addEventListener("backpex:sidebar-section-mounted", this.onSidebarSectionMounted)
    window.addEventListener("backpex:sidebar-section-toggled", this.onSidebarSectionToggled)
  },
  destroyed() {
    window.removeEventListener("backpex:sidebar-section-mounted", this.onSidebarSectionMounted)
    window.removeEventListener("backpex:sidebar-section-toggled", this.onSidebarSectionToggled)
  },
  onSidebarSectionMounted(e) {
    const open = localStorage.getItem(`section-opened-${e.target.dataset.id}`) === 'true'
    const checkbox = e.target.querySelector("input[type='checkbox']")

    if (open) {
      checkbox.setAttribute("checked", true)
    } else {
      checkbox.removeAttribute("checked")
    }
  },
  onSidebarSectionToggled(e) {
    const container = e.target.closest(".collapse")
    const checkbox = container.querySelector("input[type='checkbox']")

    localStorage.setItem(`section-opened-${container.dataset.id}`, checkbox.checked)
  }
}
