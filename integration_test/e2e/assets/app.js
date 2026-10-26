// The JavaScript of the test app: Phoenix, LiveView and the Backpex hooks, bundled by `bun run e2e:assets`.
import '../../../deps/phoenix_html/priv/static/phoenix_html.js'
import { Socket } from '../../../deps/phoenix/priv/static/phoenix.mjs'
import { LiveSocket } from '../../../deps/phoenix_live_view/priv/static/phoenix_live_view.esm.js'
import { Hooks as BackpexHooks, backpexParams } from '../../../assets/js/backpex.js'

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute('content')

const liveSocket = new LiveSocket('/live', Socket, {
  params: backpexParams({ _csrf_token: csrfToken }),
  hooks: BackpexHooks
})

liveSocket.connect()

window.liveSocket = liveSocket
