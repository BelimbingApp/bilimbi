// Shared shell disclosures. Authorization and preference writes remain at the
// authenticated LiveView edge; the browser owns focus and in-flight feedback.
export default class ShellControls {
  constructor(hook) {
    this.hook = hook
    this.root = hook.el
    this.pending = false
    this.online = true
    this.onClick = event => this.click(event)
    this.onKey = event => this.key(event)
    this.onTheme = ({detail}) => {
      this.root.dataset.themeChoice = detail.theme
      this.apply()
    }
    document.addEventListener("click", this.onClick)
    document.addEventListener("keydown", this.onKey)
    window.addEventListener("phx:theme-changed", this.onTheme)
    this.apply()
  }

  destroy() {
    clearTimeout(this.timer)
    document.removeEventListener("click", this.onClick)
    document.removeEventListener("keydown", this.onKey)
    window.removeEventListener("phx:theme-changed", this.onTheme)
  }

  panels() { return [...this.root.querySelectorAll("[data-account-panel], [data-timezone-panel]")] }
  trigger(panel) { return this.root.querySelector(`[aria-controls="${panel.id}"]`) }
  close(panel, restore = false) {
    panel.hidden = true
    this.trigger(panel)?.setAttribute("aria-expanded", "false")
    if (restore) this.trigger(panel)?.focus()
  }
  closeAll(restore = false) {
    for (const panel of this.panels()) if (!panel.hidden) this.close(panel, restore)
  }
  toggle(button) {
    const panel = document.getElementById(button.getAttribute("aria-controls"))
    const open = panel.hidden
    this.closeAll()
    panel.hidden = !open
    button.setAttribute("aria-expanded", String(open))
    if (open) panel.querySelector("a[href], button:not([disabled])")?.focus()
  }
  click(event) {
    const button = event.target.closest("button")
    if (button && this.root.contains(button)) {
      if (button.matches("[data-account-toggle], [data-timezone-toggle]")) {
        this.toggle(button)
        return
      }
      if (button.matches("[data-preference-kind]")) {
        this.save(button.dataset.preferenceKind, button.dataset.preferenceValue)
        return
      }
    }
    for (const panel of this.panels()) {
      if (!panel.hidden && !panel.contains(event.target)) this.close(panel)
    }
  }
  key(event) {
    const panel = this.panels().find(panel => !panel.hidden)
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
  feedback(message, error = false) {
    const region = this.root.querySelector("#app-preference-feedback")
    if (!region) return
    region.hidden = false
    region.textContent = message
    region.classList.toggle("text-danger", error)
  }
  connection(online) {
    this.online = online
    if (!online && this.pending) this.feedback("Connection lost. Save could not be confirmed. Reconnect to check your saved preference.", true)
    if (online) {
      clearTimeout(this.timer)
      this.pending = false
    }
    this.apply()
  }
  save(kind, value) {
    if (this.pending || !this.online) return
    this.pending = true
    this.apply()
    this.feedback("Saving display preference…")
    this.timer = setTimeout(() => {
      this.feedback("Save could not be confirmed. Reconnect or reload to check your saved preference.", true)
    }, 12000)
    this.hook.pushEvent("shell:preference", {kind, value}, reply => {
      clearTimeout(this.timer)
      this.pending = false
      if (reply.ok) {
        const preferences = reply.preferences
        this.root.dataset.themeChoice = preferences.theme
        this.root.dataset.displayMode = preferences.mode
        this.root.dataset.displayTimezone = preferences.timezone
        this.feedback(kind === "theme" ? "Theme saved." : "Time display saved.")
        this.closeAll(true)
      } else {
        this.feedback("Could not save display preference. Your previous choice is still selected. Try again.", true)
      }
      this.apply()
    })
  }
  apply() {
    const theme = this.root.dataset.themeChoice || "system"
    if (theme === "system") delete document.documentElement.dataset.theme
    else document.documentElement.dataset.theme = theme
    const mode = this.root.dataset.displayMode || "company"
    for (const button of this.root.querySelectorAll("[data-preference-kind]")) {
      button.disabled = this.pending || !this.online
      button.setAttribute("aria-pressed", String(button.dataset.preferenceValue === (button.dataset.preferenceKind === "theme" ? theme : mode)))
    }
    for (const label of this.root.querySelectorAll("[data-timezone-label]")) label.textContent = {company: "Company", local: "Local", utc: "UTC"}[mode]
    for (const button of this.root.querySelectorAll("[data-timezone-toggle]")) button.title = `Time display: ${{company: this.root.dataset.displayTimezone, local: "This device’s local time", utc: "UTC"}[mode]}`
  }
}
