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
const MultiSelectDismiss = {
  mounted() {
    this.onFocusOut = (e) => {
      if (e.relatedTarget && this.el.contains(e.relatedTarget)) return

      this.js().exec(this.el.dataset.dismiss)
    }

    this.el.addEventListener("focusout", this.onFocusOut)
  },

  destroyed() {
    this.el.removeEventListener("focusout", this.onFocusOut)
  },
}

export default MultiSelectDismiss
