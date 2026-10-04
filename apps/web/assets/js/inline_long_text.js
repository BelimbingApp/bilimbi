import {commit as commitValue, focusTrigger, settle as settleCommit} from "./inline_commit.js"

const InlineLongText = {
  mounted() {
    this.init()
  },

  init() {
    this.triggerEl = this.el.querySelector('[data-role="trigger"]')
    this.inputEl = this.el.querySelector('textarea[data-role="input"]')
    this.textEl = this.el.querySelector('[data-role="text"]')
    this.originalValue = this.el.dataset.value ?? this.inputEl?.value ?? ""
    this.inFlight = false

    if (this.inputEl) this.bindInput()
  },

  updated() {
    this.settle()
    this.syncNodes()
    this.syncValue()
  },

  syncNodes() {
    const input = this.el.querySelector('textarea[data-role="input"]')
    if (input && input !== this.inputEl) {
      this.inputEl = input
      this.bindInput()
    }

    this.triggerEl = this.el.querySelector('[data-role="trigger"]')
    this.textEl = this.el.querySelector('[data-role="text"]')
  },

  bindInput() {
    this.originalValue = this.el.dataset.value ?? this.inputEl.value
    this.canceling = false

    this.inputEl.addEventListener("keydown", (event) => {
      if (event.key === "Escape") {
        event.preventDefault()
        event.stopPropagation()
        this.cancel()
      }
    })

    this.inputEl.addEventListener("blur", () => {
      if (!this.inputEl || this.inFlight || this.canceling) return
      this.commit()
    })
  },

  syncValue() {
    if (!this.inputEl || document.activeElement === this.inputEl) return

    // `data-value` is the server's committed value. A textarea's live value
    // stops following its text node after typing, so never read it as a patch.
    const serverValue = this.el.dataset.value
    if (serverValue !== undefined) {
      this.originalValue = serverValue
      if (!this.inFlight) this.inputEl.value = serverValue
    }
  },

  commit() {
    const value = this.inputEl.value
    const allowEmpty = this.el.hasAttribute("data-allow-empty")

    if (value === this.originalValue || (value.trim() === "" && !allowEmpty)) {
      this.pushEventTo(this.el, this.el.dataset.cancelEvent, {})
      return
    }

    this.inFlight = true
    commitValue(this, {value})
  },

  cancel() {
    this.canceling = true
    this.pushEventTo(this.el, this.el.dataset.cancelEvent, {})
    this.settle()
    focusTrigger(this)
  },

  settle() {
    this.inFlight = false
    settleCommit(this)
  },
}

export default InlineLongText
