// Companion to the `reveal` option of `<.input type="password">`.
//
// The show/hide toggle itself is a LiveView JS command on the button, so the
// swapped `type`, accessible name and glyph stay sticky across patches. This
// hook does what the command cannot: a pointer press on the toggle must not
// pull focus out of the input, and the caret must survive the type swap
// (browsers reset the selection when `type` changes), so the user can look,
// then keep typing where they were. Keyboard activation still focuses the
// button as usual.
const SecretReveal = {
  mounted() {
    this.el.addEventListener("mousedown", (e) => e.preventDefault())

    this.el.addEventListener("click", () => {
      const input = document.getElementById(this.el.getAttribute("aria-controls"))
      if (!input || document.activeElement !== input) return

      const {selectionStart, selectionEnd} = input
      // LiveView applies the command in its own window listener, after this
      // one; a macrotask lands after the swap, a microtask would not.
      setTimeout(() => input.setSelectionRange(selectionStart, selectionEnd), 0)
    })
  },
}

export default SecretReveal
