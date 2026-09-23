// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/web"
import topbar from "../vendor/topbar"
import AppShell from "./app_shell"
import DateTime from "./date_time"
import BrowserTimeZone from "./browser_time_zone"
import InlineEdit from "./inline_edit"
import DashboardSort from "./dashboard_sort"
import MultiSelectDismiss from "./multi_select"
import SecretReveal from "./secret_reveal"
import Modal from "./modal"
import FlashAutoDismiss from "./flash_auto_dismiss"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, AppShell, DateTime, BrowserTimeZone, InlineEdit, DashboardSort, MultiSelectDismiss, SecretReveal, Modal, FlashAutoDismiss},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// A pressed `phx-disable-with` control is disabled and relabelled while the
// round trip is in flight, but LiveView writes no `aria-busy`, so the wait is
// silent to assistive technology. `phx:push` carries the promise that resolves
// when LiveView undoes its own loading state, so the mirror cannot outlive it.
// The marker records that the mirror owns this `aria-busy`: when the reply
// renders a server-known busy state, the undo patch drops the marker and the
// server's attribute stands.
//
// This carries every `phx-disable-with` control in the product and no test
// exercises it -- there is no JS runner here. It rests on three things that
// hold in phoenix_live_view 1.2.9 and are not ours to guarantee:
//
//   1. `phx:push` details keep `isLoading` and a `loadingComplete` promise;
//   2. LiveView keeps dispatching `phx:push` on the submitter -- once a submit
//      has one, `putRef` skips every element that is neither it nor the form,
//      so the button we relabel is exactly the one we hear about;
//   3. the reply patch strips `data-busy-mirror` before `phx:undo-loading`
//      resolves, so the marker cannot outlive the wait and delete an
//      `aria-busy` the server rendered itself.
//
// Re-read them when the LiveView pin moves.
const BUSY_MIRROR = "data-busy-mirror"

window.addEventListener("phx:push", ({target, detail}) => {
  if(!detail.isLoading || !detail.loadingComplete){ return }
  if(!target.hasAttribute("phx-disable-with") || target.hasAttribute("aria-busy")){ return }

  target.setAttribute("aria-busy", "true")
  target.setAttribute(BUSY_MIRROR, "")
  detail.loadingComplete.then(() => {
    if(target.hasAttribute(BUSY_MIRROR)){
      target.removeAttribute(BUSY_MIRROR)
      target.removeAttribute("aria-busy")
    }
  })
})

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}
