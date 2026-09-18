// Gives the server-rendered <dialog> behind <.modal> real modal semantics.
//
// The server decides whether a dialog exists: it renders the element while the
// workflow it hosts is in progress and removes it when that workflow ends. The
// browser owns everything else a modal needs — the top layer, an inert page
// behind it, focus containment and Escape — through showModal(). This hook only
// bridges the two: it promotes the server's dialog to a modal one on mount,
// forwards every close request to the server, and returns focus to the control
// that opened the dialog once the server has removed it.
//
// Which control that is cannot be read from document.activeElement alone: a
// browser that does not focus a <button> on click leaves focus on <body>, and
// the dialog would then have nowhere to return it to. One capture-phase
// pointerdown listener records the control the user activated instead. It is
// armed when app.js imports this module, because the click that opens the
// first dialog of a page session lands before any dialog exists to mount a
// hook. A keyboard activation needs no listener: the control holds focus while
// it is activated, so document.activeElement is already the opener.
const ACTIVATION_TARGETS = "button, a[href], [tabindex]"

let lastActivated = null

function rememberActivation({target}) {
  lastActivated = target instanceof Element ? target.closest(ACTIVATION_TARGETS) : null
}

document.addEventListener("pointerdown", rememberActivation, true)

const Modal = {
  mounted() {
    this.opener = this.openerFrom(lastActivated) || this.openerFrom(document.activeElement)

    // The server renders `open` so a later patch never strips the attribute
    // and closes the dialog under the user. An open non-modal dialog cannot
    // be promoted in place, so it is reopened as modal before anything paints.
    if (this.el.open) this.el.close()
    this.el.showModal()

    // Escape asks to close. The dialog stays open until the server removes
    // it, so there is one source of truth for whether the workflow is live.
    this.el.addEventListener("cancel", (e) => {
      e.preventDefault()
      this.requestClose()
    })

    // A close the browser refuses to cancel (a repeated Escape) or a script
    // close still tells the server, so the two cannot disagree for long.
    this.el.addEventListener("close", () => {
      if (!this.el.open) this.requestClose()
    })
  },

  destroyed() {
    const opener = this.opener
    if (opener && opener.isConnected && typeof opener.focus === "function") {
      opener.focus()
    }
  },

  openerFrom(candidate) {
    if (!candidate || candidate === document.body) return null
    if (!candidate.isConnected || this.el.contains(candidate)) return null

    return typeof candidate.focus === "function" ? candidate : null
  },

  requestClose() {
    const cancel = this.el.getAttribute("data-cancel")
    if (cancel) this.liveSocket.execJS(this.el, cancel)
  },
}

export default Modal
