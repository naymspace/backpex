import 'phoenix_html'
import * as Sentry from '@sentry/browser'
import topbar from 'topbar'
import { Socket } from 'phoenix'
import { LiveSocket } from 'phoenix_live_view'
import { Hooks as BackpexHooks } from 'backpex'

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
  params: {_csrf_token: csrfToken},
  hooks: {...BackpexHooks}
})

liveSocket.connect()

/**
 * Globals
 */
window.liveSocket = liveSocket
