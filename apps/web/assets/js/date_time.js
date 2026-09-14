const DateTime = {
  mounted() {
    this.onDisplay = () => this.renderDateTime()
    window.addEventListener("bilimbi:display-changed", this.onDisplay)
    this.renderDateTime()
  },
  updated() { this.renderDateTime() },
  destroyed() { window.removeEventListener("bilimbi:display-changed", this.onDisplay) },
  renderDateTime() {
    const value = new Date(this.el.dateTime)
    if (Number.isNaN(value.getTime())) return
    const shell = this.el.dataset.followShell === "true" ? this.el.closest("#app-shell") : null
    const mode = shell?.dataset.displayMode || this.el.dataset.mode || "local"
    const format = this.el.dataset.format
    const timeZone = mode === "local"
      ? Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC"
      : mode === "company" ? shell?.dataset.displayTimezone || this.el.dataset.zone || "UTC" : "UTC"
    // Server rendering remains a complete no-JS fallback. Every instant uses
    // the same hook so streamed rows also follow a newly saved shell mode.
    if (mode === "utc") {
      const iso = value.toISOString()
      const date = `${iso.slice(8, 10)}/${iso.slice(5, 7)}/${iso.slice(0, 4)}`
      const time = iso.slice(11, 16)
      this.el.textContent = `${format === "date" ? date : format === "time" ? time : `${date}, ${time}`} UTC`
    } else {
      const options = {timeZone}
      if (format !== "time") Object.assign(options, {day: "2-digit", month: "2-digit", year: "numeric"})
      if (format !== "date") Object.assign(options, {hour: "2-digit", minute: "2-digit"})
      if (format === "datetime") options.timeZoneName = "short"
      try {
        this.el.textContent = new Intl.DateTimeFormat(undefined, options).format(value)
      } catch {
        // Keep the truthful server fallback if this browser cannot render a zone.
        return
      }
    }
    this.el.dataset.timezone = timeZone
    this.el.title = `Rendered in ${timeZone}`
  },
}
export default DateTime
