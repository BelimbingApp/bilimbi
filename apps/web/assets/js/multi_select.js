// Companion to `<.multi_select>`. Opening, closing and `aria-expanded` are
// LiveView JS commands on the markup, so they stay sticky across patches.
//
// This hook runs two of them, because LiveView reads `phx-blur` and
// `phx-keydown` from the event target alone and never from an ancestor:
// closing when focus leaves the field -- Tab past the last option, or the
// window going away, which only `relatedTarget` can tell from a move inside
// -- and Escape, which has to reach the list from wherever focus actually
// is. Binding those per element instead would need one binding on every
// option, and the `phx-keydown` match would stop every key reaching the
// page's own `phx-window-keydown` handlers. The commands come from the
// wrapper, so there is one definition of "closed", and only Escape moves
// focus.
//
// Escape listens on `window`, not the field: Safari and macOS Firefox blur
// without focusing the button being pressed, so a list opened by mouse there
// is open while focus sits on `body`, and a listener on the field would never
// see the key. It is attached only while the list is open, so no closed field
// is watching keys and no other Escape handler on the page loses one. The
// trigger's `aria-expanded` is the single record of open, so observing that
// one attribute catches every path that opens or closes the list -- the
// trigger, click-away, focus leaving, and Escape closing it again.
//
// That same blur-without-focus is why a pointer press starting inside the
// field is not focus leaving it, even when the browser reports no new target.
// The click that press belongs to already owns the toggle: dismissing on the
// blur would close the list and let the same click reopen it, so the trigger
// could never close it there. The press ends on the release, which arrives
// even when the click never does -- dragged off the field, a right-click, or
// a touch that became a scroll.
const MultiSelectDismiss = {
  mounted() {
    this.pressing = false
    this.listening = false
    this.trigger = this.el.querySelector("[aria-expanded]")

    this.onPointerDown = () => (this.pressing = true)
    this.onPressEnd = () => (this.pressing = false)

    this.onKeyDown = (e) => {
      if (e.key !== "Escape") return

      this.js().exec(this.el.dataset.escape)
    }

    this.onFocusOut = (e) => {
      if (this.pressing) {
        this.pressing = false
        return
      }

      if (e.relatedTarget && this.el.contains(e.relatedTarget)) return

      this.js().exec(this.el.dataset.dismiss)
    }

    this.syncEscape = () => {
      const open = this.trigger.getAttribute("aria-expanded") === "true"
      if (open === this.listening) return

      this.listening = open

      if (open) {
        window.addEventListener("keydown", this.onKeyDown)
      } else {
        window.removeEventListener("keydown", this.onKeyDown)
      }
    }

    this.expansion = new MutationObserver(this.syncEscape)
    this.expansion.observe(this.trigger, {attributeFilter: ["aria-expanded"]})

    this.el.addEventListener("pointerdown", this.onPointerDown)
    this.el.addEventListener("focusout", this.onFocusOut)
    window.addEventListener("pointerup", this.onPressEnd)
    window.addEventListener("pointercancel", this.onPressEnd)

    this.syncEscape()
  },

  destroyed() {
    this.expansion.disconnect()
    this.el.removeEventListener("pointerdown", this.onPointerDown)
    this.el.removeEventListener("focusout", this.onFocusOut)
    window.removeEventListener("keydown", this.onKeyDown)
    window.removeEventListener("pointerup", this.onPressEnd)
    window.removeEventListener("pointercancel", this.onPressEnd)
  },
}

export default MultiSelectDismiss
