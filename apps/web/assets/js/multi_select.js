// Companion to `<.multi_select>`. Opening, closing and `aria-expanded` are
// LiveView JS commands on the markup, so they stay sticky across patches.
//
// This hook runs two of them, because LiveView reads `phx-blur` and
// `phx-keydown` from the event target alone and never from an ancestor:
// closing when focus leaves the field -- Tab past the last option, or the
// window going away, which only `relatedTarget` can tell from a move inside
// -- and Escape from any focus stop in the menu, which a listener here takes
// by bubbling. Binding those per element instead would need one binding on
// every option, and the `phx-keydown` match would stop every key reaching the
// page's own `phx-window-keydown` handlers. The commands come from the
// wrapper, so there is one definition of "closed", and only Escape moves
// focus.
//
// A pointer press that starts inside the field is not focus leaving it, even
// when the browser reports no new target. Safari and macOS Firefox blur
// without focusing the button or checkbox being pressed, and the click that
// press belongs to already owns the toggle: dismissing on that blur would
// close the list and let the same click reopen it, so the trigger could never
// close it there. The press ends on the release, which arrives even when the
// click never does -- dragged off the field, a right-click, or a touch that
// became a scroll.
const MultiSelectDismiss = {
  mounted() {
    this.pressing = false

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

    this.el.addEventListener("pointerdown", this.onPointerDown)
    this.el.addEventListener("keydown", this.onKeyDown)
    this.el.addEventListener("focusout", this.onFocusOut)
    window.addEventListener("pointerup", this.onPressEnd)
    window.addEventListener("pointercancel", this.onPressEnd)
  },

  destroyed() {
    this.el.removeEventListener("pointerdown", this.onPointerDown)
    this.el.removeEventListener("keydown", this.onKeyDown)
    this.el.removeEventListener("focusout", this.onFocusOut)
    window.removeEventListener("pointerup", this.onPressEnd)
    window.removeEventListener("pointercancel", this.onPressEnd)
  },
}

export default MultiSelectDismiss
