// Dismisses a transient flash after the delay the server wrote on it.
//
// The layout's flash group attaches this hook only to `:success` and `:info`
// messages; a warning or an error never carries it, so nothing a person must
// act on can disappear on a timer. Dismissal reuses the element's own click
// command — clear the flash on the server, then hide it — so a timed dismissal
// and a clicked one leave the same state behind.
//
// The pointer or keyboard focus on the message pauses the timer: someone
// reading or reaching for the close button is not done with it.
const FlashAutoDismiss = {
  mounted() {
    this.delay = Number(this.el.dataset.autoDismissMs)
    if (!(this.delay > 0)) return

    this.dismiss = () => {
      this.timer = null
      const command = this.el.getAttribute("phx-click")
      if (command) this.liveSocket.execJS(this.el, command, "click")
    }
    this.pause = () => this.stop()
    this.resume = () => this.start()

    this.el.addEventListener("mouseenter", this.pause)
    this.el.addEventListener("focusin", this.pause)
    this.el.addEventListener("mouseleave", this.resume)
    this.el.addEventListener("focusout", this.resume)
    this.start()
  },

  destroyed() {
    this.stop()
  },

  start() {
    this.stop()
    this.timer = window.setTimeout(this.dismiss, this.delay)
  },

  stop() {
    if (this.timer) window.clearTimeout(this.timer)
    this.timer = null
  },
}

export default FlashAutoDismiss
