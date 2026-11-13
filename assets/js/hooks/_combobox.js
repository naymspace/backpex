/**
 * The behaviour of `Backpex.HTML.Combobox.combobox/1`.
 *
 * The server renders all markup, including the selected state, and the hook
 * only toggles attributes (`hidden`, `aria-*`, `data-*`), sets input values and
 * clones the server-rendered badge template. It knows no class names and no
 * texts, so the styling lives in HEEx as variants on those attributes.
 *
 * The selection is always read from the form inputs. A change updates them
 * and the display right away, then dispatches `input` and `change` on the
 * anchor input, so LiveView sends the form's `phx-change`. After a patch the
 * server-rendered inputs are the truth again: `updated()` re-derives the state
 * from the DOM and re-applies what only the client knows (open popup, query,
 * active option, position), because morphdom strips attributes the server did
 * not render.
 *
 * Parts are looked up by `data-part` when needed instead of in `mounted()`,
 * as a patch can re-create them while the hook stays mounted.
 *
 * The popup is a manual popover in the top layer, so nothing clips it, and
 * Floating UI keeps it next to the control.
 *
 * Document listeners and the positioning only exist while the popup is open,
 * so pages with many comboboxes don't pay an event-handler tax for closed
 * ones.
 */
import { autoUpdate, computePosition, flip, offset, shift, size } from '@floating-ui/dom'

const TYPEAHEAD_RESET_MS = 500
const POPUP_OFFSET = 4
const VIEWPORT_MARGIN = 8
const FOCUSABLE = 'a[href], button, input, select, textarea, [tabindex]'
const SELECT_ALL_BUTTONS = '[data-part="select-all-button"], [data-part="deselect-all-button"]'

/**
 * Lowercases a text and strips its diacritics, so that "Zürich" matches "zur".
 */
export function normalizeText (text) {
  return String(text ?? '')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
}

/**
 * Whether a label contains the query, ignoring case and diacritics.
 */
export function matchesQuery (label, query) {
  const needle = normalizeText(query).trim()
  return needle === '' || normalizeText(label).includes(needle)
}

/**
 * The index of the option to activate when moving from `current` in
 * `direction` ('next', 'previous', 'first' or 'last'), considering only the
 * indexes whose entry in `enabled` is true. It does not wrap around: at either
 * end it stays on `current`. Without a current option (-1), 'next' starts at
 * the first and 'previous' at the last option. Returns -1 when no option is
 * enabled.
 */
export function nextEnabledIndex (enabled, current, direction) {
  const indexes = enabled.flatMap((isEnabled, index) => (isEnabled ? [index] : []))
  if (indexes.length === 0) return -1

  const first = indexes[0]
  const last = indexes[indexes.length - 1]

  switch (direction) {
    case 'first': return first
    case 'last': return last
    case 'next':
      if (current < 0) return first
      return indexes.find((index) => index > current) ?? (enabled[current] ? current : last)
    case 'previous':
      if (current < 0) return last
      return indexes.findLast((index) => index < current) ?? (enabled[current] ? current : first)
    default: return current
  }
}

/**
 * The index of the option a typeahead buffer selects, or -1. It searches the
 * enabled labels that start with the buffer, beginning after `current` and
 * wrapping around. A buffer of one repeated character ("aaa") cycles through
 * the labels starting with that character, as in a native select.
 */
export function typeaheadIndex (labels, enabled, buffer, current) {
  const normalized = normalizeText(buffer)
  if (normalized === '') return -1

  const repeated = [...normalized].every((char) => char === normalized[0])
  const prefix = repeated ? normalized[0] : normalized
  // A longer buffer refines the current match, so the current option is
  // checked first; a repeated character moves on to the next match.
  const start = repeated || current < 0 ? current + 1 : current
  const count = labels.length

  for (let step = 0; step < count; step++) {
    const index = (start + step) % count
    if (enabled[index] && normalizeText(labels[index]).startsWith(prefix)) return index
  }

  return -1
}

function isPrintableKey (event) {
  return event.key.length === 1 && !event.ctrlKey && !event.metaKey && !event.altKey
}

export default {
  mounted () {
    this.isOpen = false
    this.query = ''
    this.activeValue = null
    this.labels = new Map()
    this.typeahead = ''
    this.typeaheadTimer = null
    this.searchTimer = null
    this.searchSeq = 0
    this.searchPending = false
    this.lastPushedQuery = ''
    this.closeOnFocusMove = false
    this.openController = null
    this.stopAutoUpdate = null
    this.popupMaxHeight = Infinity
    this.controller = new AbortController()

    const options = { signal: this.controller.signal }
    this.el.addEventListener('click', (event) => this.handleClick(event), options)
    this.el.addEventListener('mousedown', (event) => this.handleMousedown(event), options)
    this.el.addEventListener('pointermove', (event) => this.handlePointermove(event), options)
    this.el.addEventListener('keydown', (event) => this.handleKeydown(event), options)
    this.el.addEventListener('keyup', (event) => this.handleKeyup(event), options)
    this.el.addEventListener('focusout', (event) => this.handleFocusout(event), options)
    this.el.addEventListener('focusin', () => { if (this.isOpen) this.syncOpenState() }, options)
    this.el.addEventListener('input', (event) => this.handleSearchEvent(event), options)
    this.el.addEventListener('change', (event) => this.handleSearchEvent(event), options)
    this.el.addEventListener('combobox:open', () => this.open(), options)
    this.el.addEventListener('combobox:close', () => this.close(), options)
    this.el.addEventListener('combobox:clear', () => this.setSelection([]), options)
    this.el.addEventListener('combobox:select-all', () => this.selectAll(), options)

    this.rememberLabels()
  },
  updated () {
    this.rememberLabels()
    this.syncOptions(this.selectedValues())

    if (this.isOpen) {
      const popup = this.part('popup')
      if (!popup) {
        this.close()
        return
      }
      if (!popup.matches(':popover-open')) popup.showPopover()

      // LiveView keeps the value of the focused input; restore it in case
      // focus is elsewhere in the popup, e.g. on a button of the footer.
      const search = this.part('search')
      if (search && search.value !== this.query) search.value = this.query

      this.filterOptions()
      const active = this.optionByValue(this.activeValue)
      this.setActive(active && this.isNavigable(active) ? this.activeValue : this.firstNavigableValue(), { scroll: false })
      // The patch may have removed the inline position or re-created the
      // control or the popup.
      this.startPositioning()
    }

    this.el.toggleAttribute('data-loading', this.searchPending)
    this.part('listbox')?.toggleAttribute('aria-busy', this.searchPending)
    this.syncOpenState()
  },
  destroyed () {
    this.controller.abort()
    this.openController?.abort()
    this.stopPositioning()
    clearTimeout(this.typeaheadTimer)
    clearTimeout(this.searchTimer)
  },

  // Parts

  part (name) {
    return this.el.querySelector(`[data-part="${name}"]`)
  },
  options () {
    const listbox = this.part('listbox')
    return listbox ? Array.from(listbox.querySelectorAll('[data-part="option"]')) : []
  },
  optionByValue (value) {
    if (value === null) return null
    return this.options().find((option) => option.dataset.value === value) || null
  },
  activeOption () {
    return this.optionByValue(this.activeValue)
  },
  isMultiple () {
    return this.el.hasAttribute('data-multiple')
  },
  max () {
    const max = parseInt(this.el.dataset.max, 10)
    return Number.isNaN(max) ? Infinity : max
  },
  isServerSearch () {
    return this.el.hasAttribute('data-on-search')
  },
  isVisible (option) {
    return !option.hidden && !option.closest('[data-part="group"]')?.hidden
  },
  isNavigable (option) {
    return this.isVisible(option) && option.getAttribute('aria-disabled') !== 'true'
  },
  firstNavigableValue () {
    return this.options().find((option) => this.isNavigable(option))?.dataset.value ?? null
  },
  label (value) {
    return this.labels.get(value) ?? value
  },

  // Remembers the label of every value the hook has seen, so it can label a
  // badge whose option the server no longer renders, e.g. after a search.
  rememberLabels () {
    for (const option of this.options()) this.labels.set(option.dataset.value, option.dataset.label)
    for (const badge of this.el.querySelectorAll('[data-part="badge"]')) {
      const label = badge.querySelector('[data-part="badge-label"]')
      if (label) this.labels.set(badge.dataset.value, label.textContent)
    }
    const anchor = this.part('anchor')
    const valueLabel = this.part('value-label')
    if (!this.isMultiple() && anchor?.value && valueLabel && !valueLabel.hidden) {
      this.labels.set(anchor.value, valueLabel.textContent)
    }
  },

  // Selection

  selectedValues () {
    const anchor = this.part('anchor')
    if (!anchor) return []
    if (!this.isMultiple()) return anchor.value === '' ? [] : [anchor.value]
    return Array.from(this.part('inputs').querySelectorAll('input[type="hidden"]'), (input) => input.value)
  },
  setSelection (values) {
    const current = this.selectedValues()
    if (values.length === current.length && values.every((value, index) => value === current[index])) return

    this.writeInputs(values)
    this.renderSelection(values)
    this.syncOptions(values)
    this.notify(values)
  },
  writeInputs (values) {
    const anchor = this.part('anchor')
    if (!anchor) return

    if (!this.isMultiple()) {
      anchor.value = values[0] ?? ''
      return
    }

    const container = this.part('inputs')
    const existing = Array.from(container.querySelectorAll('input[type="hidden"]'))
    this.reconcile(container, existing, values, (input) => input.value, (value) => {
      const input = document.createElement('input')
      input.type = 'hidden'
      input.name = `${anchor.name}[]`
      input.value = value
      if (anchor.hasAttribute('form')) input.setAttribute('form', anchor.getAttribute('form'))
      return input
    })
  },
  renderSelection (values) {
    const placeholder = this.part('placeholder')
    if (placeholder) placeholder.hidden = values.length > 0

    const clear = this.part('clear')
    if (clear) clear.hidden = values.length === 0

    if (!this.isMultiple()) {
      const valueLabel = this.part('value-label')
      if (!valueLabel) return
      valueLabel.hidden = values.length === 0
      valueLabel.textContent = values.length === 0 ? '' : this.label(values[0])
      return
    }

    const container = this.part('value')
    const template = this.part('badge-template')
    if (!container || !template) return

    const existing = Array.from(container.querySelectorAll('[data-part="badge"]'))
    this.reconcile(container, existing, values, (badge) => badge.dataset.value, (value) => {
      const badge = template.content.firstElementChild.cloneNode(true)
      badge.dataset.value = value
      badge.querySelector('[data-part="badge-label"]').textContent = this.label(value)
      return badge
    })
  },
  // Makes the children of `container` one element per value, in order. It
  // keeps the elements of values that stay selected instead of re-creating
  // them, so the patch that follows the change finds them as rendered.
  reconcile (container, elements, values, valueOf, create) {
    const byValue = new Map(elements.map((element) => [valueOf(element), element]))
    for (const element of elements) {
      if (!values.includes(valueOf(element))) element.remove()
    }
    for (const value of values) container.appendChild(byValue.get(value) ?? create(value))
  },
  // Marks the selected options and, once `max` values are selected, disables
  // the others. Options the server disabled keep `data-disabled`.
  syncOptions (values) {
    const maxReached = this.isMultiple() && values.length >= this.max()

    for (const option of this.options()) {
      const selected = values.includes(option.dataset.value)
      option.setAttribute('aria-selected', String(selected))
      const disabled = option.hasAttribute('data-disabled') || (maxReached && !selected)
      if (disabled) option.setAttribute('aria-disabled', 'true')
      else option.removeAttribute('aria-disabled')
    }

    this.syncSelectAll(values)
  },
  // The values "select all" and "deselect all" act on: the options the search
  // shows, except the ones the server disabled.
  selectableValues () {
    return this.options()
      .filter((option) => this.isVisible(option) && !option.hasAttribute('data-disabled'))
      .map((option) => option.dataset.value)
  },
  // Shows the number of selected values and marks the button that has nothing
  // to do. `aria-disabled` instead of `disabled`: a button that disables
  // itself while it has focus would drop the focus to the body.
  syncSelectAll (values) {
    const count = this.part('selected-count')
    if (!count) return
    count.textContent = String(values.length)

    const selectable = this.selectableValues()
    const selected = selectable.filter((value) => values.includes(value)).length
    this.setAriaDisabled(this.part('select-all-button'), selected === selectable.length)
    this.setAriaDisabled(this.part('deselect-all-button'), selected === 0)
  },
  setAriaDisabled (element, disabled) {
    if (!element) return
    if (disabled) element.setAttribute('aria-disabled', 'true')
    else element.removeAttribute('aria-disabled')
  },
  notify (values) {
    const anchor = this.part('anchor')
    anchor.dispatchEvent(new window.Event('input', { bubbles: true }))
    anchor.dispatchEvent(new window.Event('change', { bubbles: true }))

    const value = this.isMultiple() ? values : (values[0] ?? '')
    this.el.dispatchEvent(new window.CustomEvent('combobox:change', { bubbles: true, detail: { value } }))
  },
  choose (option) {
    if (!option || option.getAttribute('aria-disabled') === 'true') return
    const value = option.dataset.value
    const values = this.selectedValues()

    if (!this.isMultiple()) {
      // Selecting the selected option again keeps it; only clearing deselects.
      this.setSelection([value])
      this.close({ focus: true })
      return
    }

    this.setActive(value, { scroll: false })
    this.setSelection(values.includes(value) ? values.filter((v) => v !== value) : [...values, value])
  },
  remove (value) {
    this.setSelection(this.selectedValues().filter((v) => v !== value))
  },
  selectAll () {
    if (!this.isMultiple()) return
    const values = this.selectedValues()
    const room = this.max() - values.length
    if (room <= 0) return

    const added = this.options()
      .filter((option) => this.isNavigable(option) && !values.includes(option.dataset.value))
      .map((option) => option.dataset.value)
      .slice(0, room)
    this.setSelection([...values, ...added])
  },
  // Deselects the options the search shows. Selected values it hides stay.
  deselectAll () {
    const selectable = this.selectableValues()
    this.setSelection(this.selectedValues().filter((value) => !selectable.includes(value)))
  },

  // Open state

  open () {
    const popup = this.part('popup')
    if (this.isOpen || !popup) return
    this.isOpen = true

    if (!popup.matches(':popover-open')) popup.showPopover()
    this.attachOpenListeners()

    const selected = this.selectedValues().map((value) => this.optionByValue(value)).find((option) => option && this.isNavigable(option))
    this.setActive(selected ? selected.dataset.value : this.firstNavigableValue(), { scroll: false })
    this.syncOpenState()
    this.part('search')?.focus({ preventScroll: true })

    // The popup's own maximum height comes from its classes; read it before
    // the positioning limits the height to the room next to the control.
    popup.style.maxHeight = ''
    const maxHeight = parseFloat(getComputedStyle(popup).maxHeight)
    this.popupMaxHeight = Number.isNaN(maxHeight) ? Infinity : maxHeight

    // Scroll to the active option once the popup has its final height.
    this.startPositioning().then(() => {
      if (this.isOpen) this.activeOption()?.scrollIntoView({ block: 'nearest' })
    })
  },
  close ({ focus = false } = {}) {
    if (!this.isOpen) return
    this.isOpen = false
    this.closeOnFocusMove = false
    this.openController?.abort()
    this.openController = null
    this.stopPositioning()

    // Move focus before hiding the popup, as hiding the focused search input
    // would drop focus to the body.
    if (focus) this.part('trigger')?.focus()

    const popup = this.part('popup')
    if (popup?.matches(':popover-open')) popup.hidePopover()

    this.typeahead = ''
    clearTimeout(this.typeaheadTimer)
    this.setActive(null)
    this.resetQuery()
    this.syncOpenState()
  },
  toggle () {
    if (this.isOpen) this.close({ focus: true })
    else this.open()
  },
  syncOpenState () {
    const trigger = this.part('trigger')
    const search = this.part('search')
    trigger?.setAttribute('aria-expanded', String(this.isOpen))
    search?.setAttribute('aria-expanded', String(this.isOpen))
    this.el.toggleAttribute('data-open', this.isOpen)

    // The search input has focus while the popup is open, unless the user
    // moved it back to the trigger, e.g. by removing a badge.
    const owner = search && document.activeElement !== trigger ? search : trigger
    const active = this.isOpen && this.activeOption()
    trigger?.removeAttribute('aria-activedescendant')
    search?.removeAttribute('aria-activedescendant')
    if (owner && active && this.isVisible(active)) owner.setAttribute('aria-activedescendant', active.id)
  },
  attachOpenListeners () {
    this.openController = new AbortController()
    const signal = this.openController.signal

    document.addEventListener('pointerdown', (event) => this.handleDocumentPointerdown(event), { capture: true, signal })
  },

  // Position

  // Keeps the popup next to the control while it is open: `autoUpdate`
  // repositions it when an ancestor scrolls, the window resizes, or the
  // control or the popup change their size or place. Returns the promise of
  // the first positioning.
  startPositioning () {
    this.stopPositioning()

    const popup = this.part('popup')
    const control = this.part('control')
    if (!this.isOpen || !popup || !control) return Promise.resolve()

    let first = null
    this.stopAutoUpdate = autoUpdate(control, popup, () => {
      const positioned = this.position(control, popup)
      first ??= positioned
    })
    return first ?? Promise.resolve()
  },
  stopPositioning () {
    this.stopAutoUpdate?.()
    this.stopAutoUpdate = null
  },
  // The popup opens below the control and flips above it when it does not
  // fit below. It is at least as wide as the control, stays inside the
  // viewport and is never taller than the room on its side.
  position (control, popup) {
    return computePosition(control, popup, {
      strategy: 'fixed',
      placement: 'bottom-start',
      middleware: [
        offset(POPUP_OFFSET),
        flip({ padding: VIEWPORT_MARGIN }),
        shift({ padding: VIEWPORT_MARGIN }),
        size({
          padding: VIEWPORT_MARGIN,
          apply: ({ availableWidth, availableHeight, rects }) => {
            const maxWidth = Math.max(0, availableWidth)
            Object.assign(popup.style, {
              minWidth: `${Math.min(rects.reference.width, maxWidth)}px`,
              maxWidth: `${maxWidth}px`,
              maxHeight: `${Math.max(0, Math.min(availableHeight, this.popupMaxHeight))}px`
            })
          }
        })
      ]
    }).then(({ x, y, placement }) => {
      if (!this.isOpen) return
      Object.assign(popup.style, { left: `${x}px`, top: `${y}px` })
      popup.dataset.placement = placement.split('-')[0]
    })
  },

  // Active option

  setActive (value, { scroll = true } = {}) {
    this.activeValue = value
    for (const option of this.options()) option.toggleAttribute('data-active', value !== null && option.dataset.value === value)

    const active = this.activeOption()
    if (active && scroll) active.scrollIntoView({ block: 'nearest' })
    this.syncOpenState()
  },
  moveActive (direction) {
    const options = this.options()
    const enabled = options.map((option) => this.isNavigable(option))
    const current = options.findIndex((option) => option.dataset.value === this.activeValue)
    const index = nextEnabledIndex(enabled, current, direction)
    if (index >= 0) this.setActive(options[index].dataset.value)
  },
  typeaheadKey (key) {
    clearTimeout(this.typeaheadTimer)
    this.typeahead += key
    this.typeaheadTimer = setTimeout(() => { this.typeahead = '' }, TYPEAHEAD_RESET_MS)

    this.open()
    const options = this.options()
    const index = typeaheadIndex(
      options.map((option) => option.dataset.label),
      options.map((option) => this.isNavigable(option)),
      this.typeahead,
      options.findIndex((option) => option.dataset.value === this.activeValue)
    )
    if (index >= 0) this.setActive(options[index].dataset.value)
  },

  // Search

  // Hides the options that don't match the query (local search only), the
  // groups without a visible option, and shows the empty state when no option
  // is visible.
  filterOptions () {
    const local = !this.isServerSearch()

    for (const option of this.options()) {
      if (local) option.hidden = !matchesQuery(option.dataset.label, this.query)
    }
    for (const group of this.el.querySelectorAll('[data-part="group"]')) {
      group.hidden = !Array.from(group.querySelectorAll('[data-part="option"]')).some((option) => !option.hidden)
    }

    const empty = this.part('empty')
    if (empty) empty.hidden = this.options().some((option) => this.isVisible(option))

    this.syncSelectAll(this.selectedValues())
  },
  search (query) {
    this.query = query

    if (this.isServerSearch()) {
      clearTimeout(this.searchTimer)
      const debounce = parseInt(this.el.dataset.searchDebounce, 10)
      this.searchTimer = setTimeout(() => this.pushSearch(query), Number.isNaN(debounce) ? 0 : debounce)
      return
    }

    this.filterOptions()
    this.setActive(this.firstNavigableValue())
  },
  pushSearch (query) {
    const seq = ++this.searchSeq
    this.lastPushedQuery = query
    this.setSearchPending(true)

    const event = this.el.dataset.onSearch
    const payload = { query, id: this.el.id }
    const target = this.el.getAttribute('phx-target')
    const result = target ? this.pushEventTo(target, event, payload) : this.pushEvent(event, payload)

    // Only the reply to the latest query ends the loading state; an earlier
    // reply arriving late must not hide the spinner of a newer search.
    const done = () => { if (seq === this.searchSeq) this.setSearchPending(false) }
    if (result && typeof result.then === 'function') result.then(done, done)
    else done()
  },
  setSearchPending (pending) {
    this.searchPending = pending
    this.el.toggleAttribute('data-loading', pending)
    this.part('listbox')?.toggleAttribute('aria-busy', pending)
  },
  resetQuery () {
    clearTimeout(this.searchTimer)
    const search = this.part('search')
    if (search) search.value = ''
    if (this.query === '' && this.lastPushedQuery === '') return
    this.query = ''

    if (!this.isServerSearch()) this.filterOptions()
    else if (this.lastPushedQuery !== '') this.pushSearch('')
  },

  // Event handlers

  handleClick (event) {
    const target = event.target

    const remove = target.closest('[data-part="badge-remove"]')
    if (remove) {
      this.remove(remove.closest('[data-part="badge"]').dataset.value)
      this.part('trigger')?.focus()
      return
    }

    if (target.closest('[data-part="clear"]')) {
      this.setSelection([])
      this.part('trigger')?.focus()
      return
    }

    if (target.closest('[data-part="trigger"]')) {
      this.toggle()
      return
    }

    const button = target.closest(SELECT_ALL_BUTTONS)
    if (button) {
      if (button.getAttribute('aria-disabled') === 'true') return
      if (button.dataset.part === 'select-all-button') this.selectAll()
      else this.deselectAll()
      return
    }

    const option = target.closest('[data-part="option"]')
    if (option && this.part('listbox')?.contains(option)) this.choose(option)
  },
  // Keeps focus on the trigger or the search input when clicking an option,
  // a badge's remove control or the popup's background; otherwise the click
  // would blur them and close the popup.
  handleMousedown (event) {
    const target = event.target
    if (target.closest('[data-part="badge-remove"]')) {
      event.preventDefault()
      return
    }
    // The select all and deselect all buttons can take focus with the
    // keyboard, but a click on them leaves it on the search input.
    if (target.closest(SELECT_ALL_BUTTONS)) {
      event.preventDefault()
      return
    }
    if (this.part('popup')?.contains(target) && !target.closest(FOCUSABLE)) event.preventDefault()
  },
  handlePointermove (event) {
    const option = event.target.closest('[data-part="option"]')
    if (!this.isOpen || !option || !this.isNavigable(option)) return
    if (option.dataset.value !== this.activeValue) this.setActive(option.dataset.value, { scroll: false })
  },
  handleKeydown (event) {
    if (event.isComposing) return

    const trigger = this.part('trigger')
    const search = this.part('search')
    const onTrigger = event.target === trigger
    const onSearch = search !== null && event.target === search

    if (event.key === 'Escape') {
      if (!this.isOpen) return
      // Only close the popup, not a surrounding modal or dropdown.
      event.preventDefault()
      event.stopPropagation()
      this.close({ focus: true })
      return
    }

    if (event.key === 'Tab') {
      // Without focusable content in the popup, Tab leaves the combobox, so
      // close the popup even if focus moves to another part of it.
      if (this.isOpen && !this.hasFocusableSlotContent()) this.closeOnFocusMove = true
      return
    }

    if (!onTrigger && !onSearch) return

    switch (event.key) {
      case 'ArrowDown':
      case 'ArrowUp':
        event.preventDefault()
        if (!this.isOpen) this.open()
        else this.moveActive(event.key === 'ArrowDown' ? 'next' : 'previous')
        return
      case 'Home':
      case 'End':
        // In the search input, Home and End move the caret.
        if (!this.isOpen || onSearch) return
        event.preventDefault()
        this.moveActive(event.key === 'Home' ? 'first' : 'last')
        return
      case 'Enter':
        // Also keeps Enter from submitting the form while the popup is open.
        event.preventDefault()
        if (!this.isOpen) this.open()
        else this.choose(this.activeOption())
        return
      case ' ':
        if (onSearch) return
        event.preventDefault()
        if (this.typeahead !== '') this.typeaheadKey(' ')
        else if (!this.isOpen) this.open()
        else this.choose(this.activeOption())
        return
      case 'Backspace':
      case 'Delete':
        if (!onTrigger) return
        event.preventDefault()
        if (this.isMultiple()) this.setSelection(this.selectedValues().slice(0, -1))
        else if (this.part('clear')) this.setSelection([])
        return
      default:
        if (!onTrigger || !isPrintableKey(event)) return
        // With a search input, opening moves focus there and the typed
        // character lands in it.
        if (search) this.open()
        else {
          event.preventDefault()
          this.typeaheadKey(event.key)
        }
    }
  },
  // A button activates on the keyup of Space; keydown already handled it.
  handleKeyup (event) {
    if (event.key === ' ' && event.target === this.part('trigger')) event.preventDefault()
  },
  handleFocusout (event) {
    if (!this.isOpen) return
    const next = event.relatedTarget
    // A null relatedTarget is a click on something that can't take focus;
    // the pointerdown listener decides whether that was outside.
    if (this.closeOnFocusMove || (next && !this.el.contains(next))) this.close()
  },
  // The search input has no name and must not reach LiveView's form handling,
  // which would send `phx-change` for every keystroke.
  handleSearchEvent (event) {
    const search = this.part('search')
    if (!search || event.target !== search) return
    event.stopPropagation()
    if (event.type === 'input') this.search(search.value)
  },
  handleDocumentPointerdown (event) {
    const target = event.target
    if (this.el.contains(target)) return
    // The label toggles the popup through the trigger.
    if (target.closest?.(`label[for="${this.part('trigger')?.id}"]`)) return
    this.close()
  },
  hasFocusableSlotContent () {
    const popup = this.part('popup')
    if (!popup) return false
    const search = this.part('search')
    return Array.from(popup.querySelectorAll(FOCUSABLE)).some((element) =>
      element !== search && !element.disabled && element.getAttribute('tabindex') !== '-1'
    )
  }
}
