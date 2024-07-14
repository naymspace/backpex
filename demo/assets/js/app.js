import { debounce } from 'lodash'
import Alpine from 'alpinejs'
import 'phoenix_html'
import * as Sentry from '@sentry/browser'
import topbar from 'topbar'
import { Socket } from 'phoenix'
import { LiveSocket } from 'phoenix_live_view'

/**
 * Alpine
 */
window.Alpine = Alpine
Alpine.start()

/**
 * Sentry
 */
const sentryMetaTag = document.querySelector('meta[name="sentry-dsn"]')
if (sentryMetaTag !== null) {
  Sentry.init({ dsn: sentryMetaTag.getAttribute('content') })
}

/**
 * topbar
 */
topbar.config({ barColors: { 0: '#29d' }, shadowColor: 'rgba(0, 0, 0, .3)' })

const debouncedTopbarShow = debounce(topbar.show, 250)
window.addEventListener('phx:page-loading-start', info => debouncedTopbarShow())
window.addEventListener('phx:page-loading-stop', function (info) {
  debouncedTopbarShow.cancel()
  topbar.hide()
})

/**
 * theme selector
 */
window.addEventListener("backpex:theme-change", (event) => {
  let form = document.querySelector("#backpex-theme-selector-form")
  let cookiePath = form.dataset.cookiePath
  let selectedTheme = form.querySelector('input[name="theme-selector"]:checked');
  let htmlElement = document.documentElement

  if (selectedTheme) {
    let xhr = new XMLHttpRequest()

    htmlElement.setAttribute("data-theme", selectedTheme.value)
    xhr.open('POST', cookiePath, true)
    xhr.setRequestHeader('Content-type', 'application/x-www-form-urlencoded');
    xhr.setRequestHeader('x-csrf-token', csrfToken)
    xhr.send(`select_theme=${selectedTheme.value}`)
  }
});

/**
 * phoenix_live_view
 */
const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute('content')

const liveSocket = new LiveSocket('/live', Socket, {
  dom: {
    onBeforeElUpdated (from, to) {
      if (from._x_dataStack) {
        window.Alpine.clone(from, to)
      }
    },
    onNodeAdded (node) {
      // Mimic autofocus for dynamically inserted elements
      if (node.nodeType === window.Node.ELEMENT_NODE && node.hasAttribute('autofocus')) {
        node.focus()

        if (node.setSelectionRange && node.value) {
          const lastIndex = node.value.length
          node.setSelectionRange(lastIndex, lastIndex)
        }
      }
    }
  },
  params: {
    _csrf_token: csrfToken
  },
  hooks: {}
})

liveSocket.connect()

/**
 * Globals
 */
window.liveSocket = liveSocket
