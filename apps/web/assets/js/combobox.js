// Client-side filtering and keyboard interaction for <.combobox>.
//
// The server owns the hidden form value and the option vocabulary. This hook
// owns only the transient query, open state and active option, so typing does
// not cause a LiveView round trip or lose the caret. A choice is committed by
// copying its value to the hidden input and dispatching a normal bubbling
// change event; forms therefore keep their existing phx-change and submit
// contracts.
const Combobox = {
  mounted() {
    this.input = this.el.querySelector('[role="combobox"]')
    this.valueInput = document.getElementById(this.el.dataset.valueId)
    this.listbox = this.el.querySelector('[role="listbox"]')
    this.noMatches = this.el.querySelector('[id$="-no-matches"]')
    this.clearButton = this.el.querySelector('[id$="-clear"]')
    this.open = false
    this.activeIndex = -1
    this.selectedValue = this.valueInput?.value || ""
    this.selectedLabel = this.input?.value || ""

    this.options = () => Array.from(this.listbox?.querySelectorAll('[role="option"]') || [])

    this.filteredOptions = () => this.options().filter(option => !option.hidden)

    this.setOpen = open => {
      this.open = open
      this.input.setAttribute("aria-expanded", String(open))
      this.listbox.hidden = !open

      if (!open) {
        this.input.removeAttribute("aria-activedescendant")
        this.activeIndex = -1
      }
    }

    this.applyFilter = () => {
      const selectionIsActive = this.input.selectionStart === 0 &&
        this.input.selectionEnd === this.input.value.length
      const query = selectionIsActive ? "" : this.input.value.trim().toLocaleLowerCase()
      const options = this.options()

      options.forEach(option => {
        const label = option.dataset.label.toLocaleLowerCase()
        const value = option.dataset.value.toLocaleLowerCase()
        option.hidden = query !== "" && !label.includes(query) && !value.includes(query)
      })

      const filtered = this.filteredOptions()
      this.noMatches.hidden = options.length === 0 || filtered.length !== 0

      if (this.activeIndex >= filtered.length) this.activeIndex = filtered.length - 1
      this.renderActive()
    }

    this.renderActive = () => {
      const filtered = this.filteredOptions()

      this.options().forEach(option => {
        const active = filtered[this.activeIndex] === option
        option.classList.toggle("bg-brand-surface", active)
        option.setAttribute("aria-selected", String(option.dataset.value === this.selectedValue))
      })

      const active = filtered[this.activeIndex]
      if (active) {
        this.input.setAttribute("aria-activedescendant", active.id)
        active.scrollIntoView({block: "nearest"})
      } else {
        this.input.removeAttribute("aria-activedescendant")
      }
    }

    this.openList = selectQuery => {
      if (!this.open) {
        this.setOpen(true)
        this.activeIndex = -1
        if (selectQuery) this.input.select()
      }

      this.applyFilter()
    }

    this.restore = () => {
      this.selectedValue = this.valueInput?.value || ""
      const selected = this.options().find(option => option.dataset.value === this.selectedValue)
      this.selectedLabel = selected?.dataset.label || ""
      this.input.value = this.selectedLabel
    }

    this.close = () => {
      this.restore()
      this.setOpen(false)
    }

    this.commit = option => {
      if (!option) return

      this.selectedValue = option.dataset.value
      this.selectedLabel = option.dataset.label
      this.input.value = this.selectedLabel
      this.valueInput.value = this.selectedValue
      this.setOpen(false)
      this.valueInput.dispatchEvent(new Event("input", {bubbles: true}))
      this.valueInput.dispatchEvent(new Event("change", {bubbles: true}))
    }

    this.cancel = () => {
      const wasOpen = this.open
      this.close()

      if (!wasOpen || !this.el.dataset.cancelEvent) return

      const event = this.el.dataset.cancelEvent
      const target = this.el.getAttribute("phx-target")
      if (target) {
        this.pushEventTo(target, event, {})
      } else {
        this.pushEvent(event, {})
      }
    }

    this.onInput = () => this.openList(false)
    this.onFocus = () => this.openList(true)
    this.onKeyDown = event => {
      const filtered = this.filteredOptions()

      if (event.key === "ArrowDown" || event.key === "ArrowUp") {
        event.preventDefault()
        this.openList(false)
        const delta = event.key === "ArrowDown" ? 1 : -1
        this.activeIndex = filtered.length === 0
          ? -1
          : this.activeIndex < 0
            ? (delta === 1 ? 0 : filtered.length - 1)
            : (this.activeIndex + delta + filtered.length) % filtered.length
        this.renderActive()
      } else if (event.key === "Enter") {
        const active = this.filteredOptions()[this.activeIndex]
        if (this.open && active) {
          event.preventDefault()
          this.commit(active)
        }
      } else if (event.key === "Escape") {
        if (this.open) {
          event.preventDefault()
          this.cancel()
        }
      }
    }

    this.onOptionMouseDown = event => {
      event.preventDefault()
      this.commit(event.currentTarget)
    }

    this.bindOptions = () => {
      this.options().forEach(option => {
        option.removeEventListener("mousedown", this.onOptionMouseDown)
        option.addEventListener("mousedown", this.onOptionMouseDown)
      })
    }

    this.bindClear = () => {
      this.clearButton?.removeEventListener("mousedown", this.onClearMouseDown)
      this.clearButton?.removeEventListener("click", this.onClear)
      this.clearButton = this.el.querySelector('[id$="-clear"]')
      this.clearButton?.addEventListener("mousedown", this.onClearMouseDown)
      this.clearButton?.addEventListener("click", this.onClear)
    }

    this.onDocumentPointerDown = event => {
      if (!this.el.contains(event.target) && this.open) this.cancel()
    }

    this.onFocusOut = event => {
      if (event.relatedTarget && this.el.contains(event.relatedTarget)) return
      requestAnimationFrame(() => {
        if (this.open && !this.el.contains(document.activeElement)) this.cancel()
      })
    }

    this.onClear = event => {
      event.preventDefault()
      this.selectedValue = ""
      this.selectedLabel = ""
      this.input.value = ""
      this.valueInput.value = ""
      this.valueInput.dispatchEvent(new Event("input", {bubbles: true}))
      this.valueInput.dispatchEvent(new Event("change", {bubbles: true}))
      this.input.focus()
      this.openList(false)
    }

    this.onClearMouseDown = event => event.preventDefault()

    this.input.addEventListener("input", this.onInput)
    this.input.addEventListener("focus", this.onFocus)
    this.input.addEventListener("keydown", this.onKeyDown)
    this.el.addEventListener("focusout", this.onFocusOut)
    this.bindOptions()
    this.bindClear()
    document.addEventListener("pointerdown", this.onDocumentPointerDown)

    this.applyFilter()
  },

  updated() {
    this.bindOptions()
    this.bindClear()
    if (!this.open) this.restore()
    this.applyFilter()
  },

  destroyed() {
    this.input.removeEventListener("input", this.onInput)
    this.input.removeEventListener("focus", this.onFocus)
    this.input.removeEventListener("keydown", this.onKeyDown)
    this.el.removeEventListener("focusout", this.onFocusOut)
    this.options().forEach(option => option.removeEventListener("mousedown", this.onOptionMouseDown))
    this.clearButton?.removeEventListener("click", this.onClear)
    this.clearButton?.removeEventListener("mousedown", this.onClearMouseDown)
    document.removeEventListener("pointerdown", this.onDocumentPointerDown)
  },
}

export default Combobox
