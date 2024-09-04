const BackpexHasMany = {
  mounted() {
    this.toggleAllButton = this.el.querySelector('[data-toggle-all-btn]')
    this.badgesList = this.el.querySelector('[data-badges-container]')
    this.selectedValuesInput = this.el.querySelector("input[type='hidden']")
    this.checkboxContainer = this.el.querySelector('[data-checkbox-container]')

    if (!this.toggleAllButton || !this.badgesList || !this.selectedValuesInput || !this.checkboxContainer) {
      console.error('BackpexHasMany Hook: One or more required elements not found')
      return
    }

    this.checkboxes = this.checkboxContainer.querySelectorAll("input[type='checkbox']")

    this.toggleAllButton.addEventListener('toggle-all', this.onToggleAll.bind(this))
    this.badgesList.addEventListener('toggle', this.onSingleToggle.bind(this))
  },
  onToggleAll(event) {
    const { checkboxValue } = event.detail
    this.setAllCheckboxes(checkboxValue)
  },
  onSingleToggle(event) {
    const { value } = event.detail
    this.toggleSingleCheckbox(value)
  },
  setAllCheckboxes(checkboxValue) {
    this.checkboxes.forEach(checkbox => {
      if (checkbox.style.display !== 'none') {
        checkbox.checked = checkboxValue
      }
    })
    this.notifyInputChange()
  },
  toggleSingleCheckbox(value) {
    const checkbox = this.el.querySelector(`input[type="checkbox"][value="${value}"]`)
    if (checkbox) {
      checkbox.checked = !checkbox.checked
      this.notifyInputChange()
    } else {
      console.warn(`BackpexHasMany Hook: Checkbox with value "${value}" not found`)
    }
  },
  notifyInputChange() {
    this.selectedValuesInput.dispatchEvent(new Event('input', { bubbles: true }))
  },
  destroyed() {
    this.toggleAllButton.removeEventListener('toggle-all', this.onToggleAll)
    this.badgesList.removeEventListener('toggle', this.onSingleToggle)
    this.searchInput.removeEventListener('input', this.onSearch)
  }
}

export default BackpexHasMany
