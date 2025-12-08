import 'phoenix_html'
import * as Sentry from '@sentry/browser'
import topbar from 'topbar'
import { Socket } from 'phoenix'
import { LiveSocket } from 'phoenix_live_view'
import { hooks as colocatedHooks } from 'phoenix-colocated/demo'
// in your app.js, just use 'backpex' like this:
// import { Hooks as BackpexHooks } from 'backpex'
import { Hooks as BackpexHooks } from '#backpex'

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
window.addEventListener('phx:page-loading-start', _info => topbar.show(250))
window.addEventListener('phx:page-loading-stop', _info => topbar.hide())

/**
 * Theme Selector
 */
BackpexHooks.BackpexThemeSelector.setStoredTheme()

/**
 * phoenix_live_view
 */
const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute('content')

const liveSocket = new LiveSocket('/live', Socket, {
  params: { _csrf_token: csrfToken },
  hooks: { ...BackpexHooks, ...colocatedHooks }
})

liveSocket.connect()

/**
 * Globals
 */
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === 'development') {
  window.addEventListener('phx:live_reload:attached', ({ detail: reloader }) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener('keydown', function (e) { keyDown = e.key })
    window.addEventListener('keyup', function (e) { keyDown = null })
    window.addEventListener('click', function (e) {
      if (keyDown === 'c') {
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if (keyDown === 'd') {
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}
