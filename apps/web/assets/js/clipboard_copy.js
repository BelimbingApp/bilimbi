// Copies the text of whichever `[data-copy-text]` element inside the hooked
// container is clicked, then tells the server whether the browser accepted
// the write. The server owns the feedback, so "Copied" appears only after the
// clipboard really holds the text; a refused write (an insecure origin, a
// denied permission, no Clipboard API at all) is reported as a failure
// rather than claimed as a success.
//
// One listener on the container serves every tile, so a patch that adds,
// removes or filters tiles needs no re-binding. The container names the
// event in `data-copy-event`; the payload is `{text, copied}`.
const ClipboardCopy = {
  mounted() {
    this.onClick = (event) => {
      const source = event.target.closest("[data-copy-text]")
      if (!source || !this.el.contains(source)) return

      const text = source.dataset.copyText
      const report = (copied) => this.pushEvent(this.el.dataset.copyEvent, {text, copied})

      let write
      try {
        write = navigator.clipboard.writeText(text)
      } catch (_error) {
        report(false)
        return
      }

      write.then(() => report(true), () => report(false))
    }

    this.el.addEventListener("click", this.onClick)
  },

  destroyed() {
    this.el.removeEventListener("click", this.onClick)
  },
}

export default ClipboardCopy
