// Gives the server-rendered <dialog> behind <.modal> real modal semantics.
//
// The server decides whether a dialog exists: it renders the element while the
// workflow it hosts is in progress and removes it when that workflow ends. The
// browser owns everything else a modal needs — the top layer, an inert page
// behind it, focus containment and Escape — through showModal(). This hook only
// bridges the two: it promotes the server's dialog to a modal one on mount,
// forwards every close request to the server, and returns focus to the control
// that opened the dialog once the server has removed it.
const FOCUSABLE = [
  "input:not([type=hidden]):not([disabled])",
  "select:not([disabled])",
  "textarea:not([disabled])",
  "button:not([disabled])",
  "a[href]",
  '[tabindex]:not([tabindex="-1"])',
].join(", ")

const Modal = {
  mounted() {
    // The control that opened the dialog still holds focus when the patch
    // that inserted the dialog lands, so it is the place to return to.
    const active = document.activeElement
    this.opener = active && active !== document.body ? active : null

    // The server renders `open` so a later patch never strips the attribute
    // and closes the dialog under the user. An open non-modal dialog cannot
    // be promoted in place, so it is reopened as modal before anything paints.
    if (this.el.open) this.el.close()
    this.el.showModal()
    this.focusInside()

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

  requestClose() {
    const cancel = this.el.getAttribute("data-cancel")
    if (cancel) this.liveSocket.execJS(this.el, cancel)
  },

  focusInside() {
    if (this.el.contains(document.activeElement)) return
    const first = this.el.querySelector("[autofocus]") || this.el.querySelector(FOCUSABLE)
    ;(first || this.el).focus()
  },
}

export default Modal
