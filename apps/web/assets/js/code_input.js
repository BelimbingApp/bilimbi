// One native input is the keyboard and accessibility contract. Decorative
// boxes follow its caret, so editing never adds eight tab stops or labels.
export default {
  mounted() {
    this.input = this.el.querySelector("input")
    this.boxes = [...this.el.querySelectorAll("[data-code-index]")]
    this.length = Number(this.el.dataset.codeLength)
    this.normalize = value => value.toUpperCase().replace(/[\s-]/g, "").slice(0, this.length)
    this.paint = () => {
      const active = Math.min(this.input.selectionStart ?? 0, this.length - 1)
      this.boxes.forEach((box, index) => {
        box.textContent = this.input.value[index] || ""
        box.toggleAttribute("data-active", document.activeElement === this.input && index === active)
      })
    }
    this.onInput = () => {
      const caret = this.normalize(this.input.value.slice(0, this.input.selectionStart)).length
      this.input.value = this.normalize(this.input.value)
      this.input.setSelectionRange(caret, caret)
      this.paint()
    }
    this.onPaste = event => {
      const text = event.clipboardData?.getData("text")
      if (text == null) return
      event.preventDefault()
      const start = this.input.selectionStart
      const end = this.input.selectionEnd
      const code = this.normalize(text)
      // A whole code replaces the field even when pasted midway through it.
      this.input.value = code.length === this.length ? code :
        this.normalize(this.input.value.slice(0, start) + code + this.input.value.slice(end))
      const caret = code.length === this.length ? this.length : Math.min(start + code.length, this.length)
      this.input.setSelectionRange(caret, caret)
      this.input.dispatchEvent(new Event("input", {bubbles: true}))
    }
    this.onClick = event => {
      const box = event.target.closest("[data-code-index]")
      if (!box) return
      this.input.focus()
      const index = Math.min(Number(box.dataset.codeIndex), this.input.value.length)
      this.input.setSelectionRange(index, index)
      this.paint()
    }
    this.input.value = this.normalize(this.input.value)
    this.input.classList.add("absolute", "opacity-0", "pointer-events-none")
    this.el.querySelector("[data-code-boxes]").hidden = false
    this.input.addEventListener("input", this.onInput)
    this.input.addEventListener("paste", this.onPaste)
    for (const event of ["focus", "blur", "keyup", "select"]) this.input.addEventListener(event, this.paint)
    this.el.addEventListener("click", this.onClick)
    this.paint()
  },
  updated() {
    this.input.classList.add("absolute", "opacity-0", "pointer-events-none")
    this.el.querySelector("[data-code-boxes]").hidden = false
    this.input.value = this.normalize(this.input.value)
    this.paint()
  },
  destroyed() {
    this.input.removeEventListener("input", this.onInput)
    this.input.removeEventListener("paste", this.onPaste)
    for (const event of ["focus", "blur", "keyup", "select"]) this.input.removeEventListener(event, this.paint)
    this.el.removeEventListener("click", this.onClick)
  },
}
