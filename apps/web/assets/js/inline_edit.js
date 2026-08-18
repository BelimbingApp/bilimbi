const InlineEdit = {
  mounted() {
    this.init()
  },

  updated() {
    this.syncValue()
  },

  init() {
    this.triggerEl = this.el.querySelector('[data-role="trigger"]')
    this.inputEl = this.el.querySelector('input[data-role="input"]')
    this.textEl = this.el.querySelector('[data-role="text"]')

    if (!this.triggerEl || !this.inputEl) return

    this.originalValue = this.inputEl.value

    this.triggerEl.addEventListener("click", () => this.startEdit())
    this.triggerEl.addEventListener("keydown", (e) => {
      if (e.key === "Enter" || e.key === " ") {
        e.preventDefault()
        this.startEdit()
      }
    })

    this.inputEl.addEventListener("keydown", (e) => {
      if (e.key === "Enter") {
        e.preventDefault()
        this.commit()
      } else if (e.key === "Escape") {
        e.preventDefault()
        this.cancel()
      }
    })

    this.inputEl.addEventListener("blur", () => {
      if (!this.inputEl.classList.contains("hidden")) {
        this.commit()
      }
    })
  },

  syncValue() {
    if (!this.inputEl || !this.textEl) return
    this.originalValue = this.inputEl.value
    if (this.textEl) {
      this.textEl.textContent = this.inputEl.value
    }
    this.inputEl.classList.add("hidden")
    this.triggerEl.classList.remove("invisible", "pointer-events-none")
  },

  startEdit() {
    this.originalValue = this.inputEl.value
    this.triggerEl.classList.add("invisible", "pointer-events-none")
    this.inputEl.classList.remove("hidden")
    this.inputEl.focus()
    this.inputEl.select()
  },

  commit() {
    const newValue = this.inputEl.value.trim()
    const id = this.el.dataset.id
    const field = this.el.dataset.field || "value"
    const saveEvent = this.el.dataset.saveEvent || "save"

    this.inputEl.classList.add("hidden")
    this.triggerEl.classList.remove("invisible", "pointer-events-none")

    if (newValue !== "" && newValue !== this.originalValue) {
      this.originalValue = newValue
      if (this.textEl) {
        this.textEl.textContent = newValue
      }
      this.pushEvent(saveEvent, {id: id, [field]: newValue})
    } else if (newValue === "") {
      this.inputEl.value = this.originalValue
    }
  },

  cancel() {
    this.inputEl.value = this.originalValue
    this.inputEl.classList.add("hidden")
    this.triggerEl.classList.remove("invisible", "pointer-events-none")
    this.triggerEl.focus()
  },
}

export default InlineEdit
