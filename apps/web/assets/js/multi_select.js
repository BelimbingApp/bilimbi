// Companion to `<.multi_select>`. Opening, closing and `aria-expanded` are
// LiveView JS commands on the markup, so they stay sticky across patches.
//
// This hook covers the one dismissal a command cannot express: focus leaving
// the field entirely -- Tab past the last option, or the window going away.
// LiveView reads `phx-blur` from the event target alone, never an ancestor,
// and only `relatedTarget` says whether the focus that arrived is still
// inside. It runs the wrapper's own dismiss command, so there is one
// definition of "closed", and it never moves focus: only Escape returns the
// user to the trigger.
//
// A pointer press that starts inside the field is not focus leaving it, even
// when the browser reports no new target. Safari and macOS Firefox blur
// without focusing the button or checkbox being pressed, and the click that
// press belongs to already owns the toggle: dismissing on that blur would
// close the list and let the same click reopen it, so the trigger could never
// close it there. The press is spent by its own click, or by the blur it
// explains.
const MultiSelectDismiss = {
  mounted() {
    this.pressing = false

    this.onPointerDown = () => (this.pressing = true)
    this.onClick = () => (this.pressing = false)

    this.onFocusOut = (e) => {
      if (this.pressing) {
        this.pressing = false
        return
      }

      if (e.relatedTarget && this.el.contains(e.relatedTarget)) return

      this.js().exec(this.el.dataset.dismiss)
    }

    this.el.addEventListener("pointerdown", this.onPointerDown)
    this.el.addEventListener("click", this.onClick)
    this.el.addEventListener("focusout", this.onFocusOut)
  },

  destroyed() {
    this.el.removeEventListener("pointerdown", this.onPointerDown)
    this.el.removeEventListener("click", this.onClick)
    this.el.removeEventListener("focusout", this.onFocusOut)
  },
}

export default MultiSelectDismiss
