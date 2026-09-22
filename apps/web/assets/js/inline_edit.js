const InlineEdit = {
  mounted() {
    this.init()
  },

  updated() {
    // A patch from the server is the reply the pending save was waiting for
    // (or a change from elsewhere); either way nothing is in flight any more.
    this.settle()
    this.syncValue()
  },

  init() {
    this.triggerEl = this.el.querySelector('[data-role="trigger"]')
    this.inputEl = this.el.querySelector('input[data-role="input"]')
    this.textEl = this.el.querySelector('[data-role="text"]')
    this.savingEl = this.el.querySelector('[data-role="saving"]')

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

    // Never disturb an open editor. A patch can land mid-typing -- a search, a
    // sort, a page change, another agent saving this row -- and closing the
    // input here would publish half-typed text as though it were saved, and
    // overwrite originalValue so Escape could no longer restore it.
    if (!this.inputEl.classList.contains("hidden")) return

    // The ATTRIBUTE, not the property: morphdom patches the attribute, but the
    // browser decouples .value from it once a user has typed. Reading the
    // property would show what was typed rather than what the server stored.
    const serverValue = this.inputEl.getAttribute("value")

    this.originalValue = serverValue === null ? this.inputEl.value : serverValue
    this.inputEl.value = this.originalValue
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
    // Clearing a value is a real edit only where the owner says the field may
    // be empty; elsewhere an emptied input is treated as "no change" so a
    // required value is never blanked by a stray Enter.
    const allowEmpty = this.el.hasAttribute("data-allow-empty")

    this.inputEl.classList.add("hidden")
    this.triggerEl.classList.remove("invisible", "pointer-events-none")

    // The displayed text is the server's to write. Painting it here made a
    // FAILED save look like a successful one: the flash said "Failed to save"
    // while the row showed the new name indefinitely, because the error branch
    // sends no patch. Leaving the text alone means a failure needs no rollback
    // -- the row simply never changed (#302).
    if ((newValue !== "" || allowEmpty) && newValue !== this.originalValue) {
      this.markSaving()
      // Addressed to the element rather than pushed bare: LiveView then
      // routes the event to the LiveComponent that rendered this field, when
      // one did (the address panels' table rows), and to the LiveView
      // otherwise (a detail page's facts). A bare pushEvent always reaches
      // the LiveView, which has no handler for a component's field.
      this.pushEventTo(this.el, saveEvent, {id: id, [field]: newValue}, () => this.settle())
    } else {
      this.inputEl.value = this.originalValue
    }
  },

  // The wait between commit and the server's reply is the one state the server
  // cannot render, so the hook announces it: `aria-busy` on the field and the
  // owner's "Saving…" text, if the markup carries one. The reply patch renders
  // the saved or failed outcome and `settle` clears the in-flight marks.
  markSaving() {
    this.el.setAttribute("aria-busy", "true")
    if (this.savingEl) this.savingEl.classList.remove("hidden")
  },

  settle() {
    this.el.removeAttribute("aria-busy")
    if (this.savingEl) this.savingEl.classList.add("hidden")
  },

  cancel() {
    this.inputEl.value = this.originalValue
    this.inputEl.classList.add("hidden")
    this.triggerEl.classList.remove("invisible", "pointer-events-none")
    this.triggerEl.focus()
  },
}

export default InlineEdit
