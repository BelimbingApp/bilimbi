// Shared shell disclosures. Authorization, preference writes and every
// rendered preference state stay at the authenticated LiveView edge; the
// browser owns theme projection, disclosure state, focus and in-flight
// feedback, and re-applies its own state after each server patch.
export default class ShellControls {
  constructor(hook) {
    this.hook = hook
    this.root = hook.el
    this.pending = false
    this.online = true
    this.openPanelId = null
    this.message = null
    this.messageError = false
    this.messageUnresolved = false
    this.onClick = event => this.click(event)
    this.onKey = event => this.key(event)
    document.addEventListener("click", this.onClick)
    document.addEventListener("keydown", this.onKey)
    this.apply()
  }

  destroy() {
    clearTimeout(this.timer)
    document.removeEventListener("click", this.onClick)
    document.removeEventListener("keydown", this.onKey)
  }

  panels() { return [...this.root.querySelectorAll("[data-account-panel], [data-timezone-panel]")] }
  openPanel() { return this.panels().find(panel => panel.id === this.openPanelId) || null }
  trigger(panel) { return this.root.querySelector(`[aria-controls="${panel.id}"]`) }
  close(panel, restore = false) {
    if (this.openPanelId === panel.id) this.openPanelId = null
    this.apply()
    if (restore) this.trigger(panel)?.focus()
  }
  closeAll(restore = false) {
    const open = this.openPanel()
    if (open) this.close(open, restore)
  }
  toggle(button) {
    const panel = document.getElementById(button.getAttribute("aria-controls"))
    const opening = this.openPanelId !== panel.id
    this.openPanelId = opening ? panel.id : null
    this.apply()
    if (opening) panel.querySelector("a[href], button:not([disabled])")?.focus()
  }
  click(event) {
    const button = event.target.closest("button")
    if (button && this.root.contains(button)) {
      if (button.matches("[data-account-toggle], [data-timezone-toggle]")) {
        this.toggle(button)
        return
      }
      if (button.matches("[data-preference-kind]")) {
        this.save(button.dataset.preferenceKind, button.dataset.preferenceValue, button)
        return
      }
    }
    const open = this.openPanel()
    if (open && !open.contains(event.target)) this.close(open)
  }
  key(event) {
    const panel = this.openPanel()
    if (!panel) return
    if (event.key === "Escape") {
      event.preventDefault()
      event.stopImmediatePropagation()
      this.close(panel, true)
    } else if (event.key === "Tab") {
      // Disclosures use the normal tab order. Close after focus leaves them.
      setTimeout(() => {
        if (!panel.contains(document.activeElement) && document.activeElement !== this.trigger(panel)) this.close(panel)
      }, 0)
    }
  }
  feedback(message, error = false, unresolved = false) {
    this.message = message
    this.messageError = error
    this.messageUnresolved = unresolved
    this.apply()
  }
  connection(online) {
    this.online = online
    if (!online && this.pending) this.feedback("Connection lost. Save could not be confirmed. Reconnect to check your saved preference.", true, true)
    if (online) {
      clearTimeout(this.timer)
      this.pending = false
      if (this.messageUnresolved) {
        this.message = null
        this.messageError = false
        this.messageUnresolved = false
      }
    }
    this.apply()
  }
  save(kind, value, origin) {
    if (this.pending || !this.online) return
    const open = this.openPanel()
    const restore = (open && open.contains(origin) && this.trigger(open)) || origin
    this.pending = true
    this.feedback("Saving display preference…", false, true)
    this.timer = setTimeout(() => {
      this.feedback("Save could not be confirmed. Reconnect or reload to check your saved preference.", true, true)
    }, 12000)
    this.hook.pushEvent("shell:preference", {kind, value}, reply => {
      clearTimeout(this.timer)
      this.pending = false
      if (reply.ok) {
        this.feedback(kind === "theme" ? "Theme saved." : "Time display saved.")
        this.closeAll()
      } else {
        this.feedback("Could not save display preference. Your previous choice is still selected. Try again.", true)
      }
      restore?.focus()
    })
  }
  apply() {
    const theme = this.root.dataset.themeChoice
    if (theme === "system") delete document.documentElement.dataset.theme
    else document.documentElement.dataset.theme = theme
    for (const button of this.root.querySelectorAll("[data-preference-kind]")) {
      button.disabled = this.pending || !this.online
    }
    for (const panel of this.panels()) {
      const open = panel.id === this.openPanelId
      panel.hidden = !open
      this.trigger(panel)?.setAttribute("aria-expanded", String(open))
    }
    const region = this.root.querySelector("#app-preference-feedback")
    if (region) {
      region.hidden = this.message === null
      region.textContent = this.message ?? ""
      region.classList.toggle("text-danger", this.messageError)
    }
  }
}
