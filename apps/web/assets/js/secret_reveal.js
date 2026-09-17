// Companion to the `reveal` option of `<.input type="password">`.
//
// The input's `type` is the only record of masked-or-shown, and a LiveView JS
// command on the button flips it, so it stays sticky across patches. This
// hook derives everything else from it: the button's accessible name, its
// title and which glyph shows. Swapping those alongside `type` is what they
// used to do, and it could invert -- LiveView applies an attribute op
// synchronously but defers a class op to a later animation frame, so two
// clicks inside one frame flipped `type` twice and the glyph once. Derived
// state cannot drift, however many clicks land: whatever `type` ends up as,
// one read of it decides the rest.
//
// A patch can reset the derived attributes, which are not sticky, so the hook
// re-derives on `updated` as well as on every change to `type`.
//
// The hook also does what the command cannot: a pointer press on the toggle
// must not pull focus out of the input, and the caret must survive the type
// swap (browsers reset the selection when `type` changes), so the user can
// look, then keep typing where they were. Keyboard activation still focuses
// the button as usual.
//
// That restore covers the click only, because the click is the only type swap
// outside a patch. A patch of a focused revealed input writes `type` twice --
// the server's `password`, then the sticky `text` back -- but LiveView reads
// the caret before the morph and puts it back after (`restoreFocus`), and a
// revealed input qualifies at both ends because its live `type` is `text`.
// Restoring it here too would be a second record of the caret.
const SecretReveal = {
  mounted() {
    this.input = document.getElementById(this.el.getAttribute("aria-controls"))
    this.showGlyph = document.getElementById(`${this.el.id}-show`)
    this.hideGlyph = document.getElementById(`${this.el.id}-hide`)

    this.sync = () => {
      const shown = this.input.getAttribute("type") === "text"
      const labels = this.el.dataset

      this.el.setAttribute("aria-label", shown ? labels.hideLabel : labels.showLabel)
      this.el.setAttribute("title", shown ? labels.hideTitle : labels.showTitle)
      this.showGlyph.classList.toggle("hidden", shown)
      this.hideGlyph.classList.toggle("hidden", !shown)
    }

    this.el.addEventListener("mousedown", (e) => e.preventDefault())

    this.el.addEventListener("click", () => {
      if (document.activeElement !== this.input) return

      const {selectionStart, selectionEnd} = this.input
      // LiveView applies the command in its own window listener, after this
      // one; a macrotask lands after the swap, a microtask would not.
      setTimeout(() => this.input.setSelectionRange(selectionStart, selectionEnd), 0)
    })

    this.masking = new MutationObserver(this.sync)
    this.masking.observe(this.input, {attributeFilter: ["type"]})

    this.sync()
  },

  updated() {
    this.sync()
  },

  destroyed() {
    this.masking.disconnect()
  },
}

export default SecretReveal
